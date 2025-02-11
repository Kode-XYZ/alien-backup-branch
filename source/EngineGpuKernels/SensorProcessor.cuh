#pragma once

#include "Object.cuh"
#include "SimulationData.cuh"
#include "CellFunctionProcessor.cuh"

class SensorProcessor
{
public:
    __inline__ __device__ static void process(SimulationData& data, SimulationStatistics& statistics);

private:
    static int constexpr NumScanAngles = 32;
    static int constexpr NumScanPoints = 64;
    static int constexpr ScanStep = 8.0f;

    __inline__ __device__ static void processCell(SimulationData& data, SimulationStatistics& statistics, Cell* cell);
    __inline__ __device__ static uint32_t getCellDensity(
        uint64_t const& timestep,
        uint32_t const& mutationId,
        uint8_t const& restrictToColor,
        SensorRestrictToMutants const& restrictToMutants,
        DensityMap const& densityMap,
        float2 const& scanPos);
    __inline__ __device__ static void searchNeighborhood(SimulationData& data, SimulationStatistics& statistics, Cell* cell, Activity& activity);
    __inline__ __device__ static void searchByAngle(SimulationData& data, SimulationStatistics& statistics, Cell* cell, Activity& activity);

    __inline__ __device__ static void flagDetectedCells(SimulationData& data, Cell* cell, float2 const& scanPos);

    __inline__ __device__ static uint8_t convertAngleToData(float angle);
    __inline__ __device__ static float convertDataToAngle(uint8_t b);
};

/************************************************************************/
/* Implementation                                                       */
/************************************************************************/

__inline__ __device__ void SensorProcessor::process(SimulationData& data, SimulationStatistics& statistics)
{
    auto& operations = data.cellFunctionOperations[CellFunction_Sensor];
    auto partition = calcBlockPartition(operations.getNumEntries());
    for (int i = partition.startIndex; i <= partition.endIndex; ++i) {
        processCell(data, statistics, operations.at(i).cell);
    }
}

__inline__ __device__ void SensorProcessor::processCell(SimulationData& data, SimulationStatistics& statistics, Cell* cell)
{
    __shared__ Activity activity;
    if (threadIdx.x == 0) {
        activity = CellFunctionProcessor::calcInputActivity(cell);
        CellFunctionProcessor::updateInvocationState(cell, activity);
    }
    __syncthreads();

    if (abs(activity.channels[0]) > cudaSimulationParameters.cellFunctionSensorActivityThreshold) {
        statistics.incNumSensorActivities(cell->color);
        switch (cell->cellFunctionData.sensor.mode) {
        case SensorMode_Neighborhood: {
            searchNeighborhood(data, statistics, cell, activity);
        } break;
        case SensorMode_FixedAngle: {
            searchByAngle(data, statistics, cell, activity);
        } break;
        }
    }
    __syncthreads();

    if (threadIdx.x == 0) {
        CellFunctionProcessor::setActivity(cell, activity);
    }
}

__inline__ __device__ uint32_t SensorProcessor::getCellDensity(
    uint64_t const& timestep,
    uint32_t const& mutationId,
    uint8_t const& restrictToColor,
    SensorRestrictToMutants const& restrictToMutants,
    DensityMap const& densityMap,
    float2 const& scanPos)
{
    uint32_t result;
    if (restrictToMutants == SensorRestrictToMutants_NoRestriction) {
        if (restrictToColor == 255) {
            result = densityMap.getCellDensity(scanPos);
        }
        if (restrictToColor != 255) {
            result = densityMap.getColorDensity(scanPos, restrictToColor);
        }
    } else {
        if (restrictToMutants == SensorRestrictToMutants_RestrictToOtherNonZeroMutants) {
            result = densityMap.getOtherMutantsDensity(timestep, scanPos, mutationId);
        }
        if (restrictToColor != 255) {
            result = min(result, densityMap.getColorDensity(scanPos, restrictToColor));
        }
    }
    return result;
}

__inline__ __device__ void
SensorProcessor::searchNeighborhood(SimulationData& data, SimulationStatistics& statistics, Cell* cell, Activity& activity)
{
    __shared__ uint32_t minDensity;
    __shared__ uint8_t restrictToColor;
    __shared__ SensorRestrictToMutants restrictToMutants;
    __shared__ float refScanAngle;
    __shared__ uint64_t lookupResult;

    if (threadIdx.x == 0) {
        refScanAngle = Math::angleOfVector(CellFunctionProcessor::calcSignalDirection(data, cell));
        minDensity = toInt(cell->cellFunctionData.sensor.minDensity * 100);
        restrictToColor = cell->cellFunctionData.sensor.restrictToColor;
        restrictToMutants = cell->cellFunctionData.sensor.restrictToMutants;
        lookupResult = 0xffffffffffffffff;
    }
    __syncthreads();

    auto const partition = calcPartition(NumScanAngles, threadIdx.x, blockDim.x);
    auto startRadius = ((restrictToColor == 255 && restrictToMutants == SensorRestrictToMutants_NoRestriction) || restrictToColor == cell->color) ? 14.0f : 0.0f;
    auto const& densityMap = data.preprocessedCellFunctionData.densityMap;
    for (float radius = startRadius; radius <= cudaSimulationParameters.cellFunctionSensorRange[cell->color]; radius += ScanStep) {
        for (int angleIndex = partition.startIndex; angleIndex <= partition.endIndex; ++angleIndex) {
            float angle = 360.0f / NumScanAngles * angleIndex;

            auto delta = Math::unitVectorOfAngle(angle) * radius;
            auto scanPos = cell->pos + delta;
            data.cellMap.correctPosition(scanPos);

            uint32_t density = getCellDensity(data.timestep, cell->mutationId, restrictToColor, restrictToMutants, densityMap, scanPos);
            if (density < minDensity) {
                continue;
            }
            float preciseAngle = angle;
            float preciseDistance = radius;
            auto relAngle = Math::subtractAngle(preciseAngle, refScanAngle);
            uint32_t relAngleData = convertAngleToData(relAngle);
            uint64_t combined = 
                static_cast<uint64_t>(preciseDistance) << 48 | static_cast<uint64_t>(density) << 40 | static_cast<uint64_t>(relAngleData) << 32;
            alienAtomicMin64(&lookupResult, combined);
        }
        __syncthreads();
    }

    if (threadIdx.x == 0) {
        if (lookupResult != 0xffffffffffffffff) {

            auto angle = convertDataToAngle(static_cast<int8_t>((lookupResult >> 32) & 0xff));
            auto distance = toFloat(lookupResult >> 48);
            auto scanAngle = refScanAngle + angle;
            auto scanPos = cell->pos + Math::unitVectorOfAngle(scanAngle) * distance;
            flagDetectedCells(data, cell, scanPos);

            activity.channels[0] = 1;                                                     //something found
            activity.channels[1] = toFloat((lookupResult >> 40) & 0xff) / 256;  //density
            activity.channels[2] = 1.0f - min(1.0f, distance / 256);                       //distance: 1 = close, 0 = far away
            activity.channels[3] = angle / 360.0f;  //angle: between -0.5 and 0.5
            cell->cellFunctionData.sensor.memoryChannel1 = activity.channels[1];
            cell->cellFunctionData.sensor.memoryChannel2 = activity.channels[2];
            cell->cellFunctionData.sensor.memoryChannel3 = activity.channels[3];
            statistics.incNumSensorMatches(cell->color);
        } else {
            activity.channels[0] = 0;  //nothing found
            activity.channels[1] = cell->cellFunctionData.sensor.memoryChannel1;
            activity.channels[2] = cell->cellFunctionData.sensor.memoryChannel2;
            activity.channels[3] = cell->cellFunctionData.sensor.memoryChannel3;
        }
    }
    __syncthreads();
}

__inline__ __device__ void
SensorProcessor::searchByAngle(SimulationData& data, SimulationStatistics& statistics, Cell* cell, Activity& activity)
{
    __shared__ uint32_t minDensity;
    __shared__ uint8_t restrictToColor;
    __shared__ SensorRestrictToMutants restrictToMutants;
    __shared__ float2 searchDelta;
    __shared__ uint64_t lookupResult;

    if (threadIdx.x == 0) {
        minDensity = toInt(cell->cellFunctionData.sensor.minDensity * 255);
        restrictToColor = cell->cellFunctionData.sensor.restrictToColor;
        restrictToMutants = cell->cellFunctionData.sensor.restrictToMutants;
        searchDelta = CellFunctionProcessor::calcSignalDirection(data, cell);
        searchDelta = Math::rotateClockwise(searchDelta, cell->cellFunctionData.sensor.angle);

        lookupResult = 0xffffffffffffffff;
    }
    __syncthreads();

    auto const partition = calcPartition(NumScanPoints, threadIdx.x, blockDim.x);
    auto startRadius = (restrictToColor == 255 || restrictToColor == cell->color) ? 14.0f : 0.0f;
    auto const& densityMap = data.preprocessedCellFunctionData.densityMap;
    for (int distanceIndex = partition.startIndex; distanceIndex <= partition.endIndex; ++distanceIndex) {
        auto distance = startRadius + cudaSimulationParameters.cellFunctionSensorRange[cell->color] / NumScanPoints * distanceIndex;
        auto scanPos = cell->pos + searchDelta * distance;
        data.cellMap.correctPosition(scanPos);

        uint32_t density = getCellDensity(data.timestep, cell->mutationId, restrictToColor, restrictToMutants, densityMap, scanPos);

        if (density < minDensity) {
            continue;
        }

        float preciseDistance = distance;
        uint64_t combined = static_cast<uint64_t>(preciseDistance) << 48 | static_cast<uint64_t>(density) << 40;
        alienAtomicMin64(&lookupResult, combined);
    }
    __syncthreads();

    if (threadIdx.x == 0) {
        if (lookupResult != 0xffffffffffffffff) {

            auto distance = toFloat(lookupResult >> 48);
            auto scanPos = cell->pos + searchDelta * distance;
            flagDetectedCells(data, cell, scanPos);

            activity.channels[0] = 1;                                                     //something found
            activity.channels[1] = static_cast<float>((lookupResult >> 40) & 0xff) / 256;  //density
            activity.channels[2] = distance / 256;                                         //distance
            statistics.incNumSensorMatches(cell->color);
        } else {
            activity.channels[0] = 0;  //nothing found
        }
    }
}

__inline__ __device__ void SensorProcessor::flagDetectedCells(SimulationData& data, Cell* cell, float2 const& scanPos)
{
    auto const& restrictToColor = cell->cellFunctionData.sensor.restrictToColor;
    auto const& restrictToMutants = cell->cellFunctionData.sensor.restrictToMutants;

    for (float dx = -3.0f; dx < 3.0f + NEAR_ZERO; dx += 1.0f) {
        for (float dy = -3.0f; dy < 3.0f + NEAR_ZERO; dy += 1.0f) {
            auto otherCell = data.cellMap.getFirst(scanPos + float2{dx, dy});
            if (!otherCell) {
                continue;
            }
            if (cell == otherCell) {
                continue;
            }
            if (restrictToColor != 255 && otherCell->color != restrictToColor) {
                continue;
            }
            if (restrictToMutants == SensorRestrictToMutants_RestrictToOtherNonZeroMutants && otherCell->mutationId != 0
                && (cell->mutationId == otherCell->mutationId || static_cast<uint8_t>(cell->mutationId & 0xff) == otherCell->ancestorMutationId)) {
                continue;
            }
            //if (restrictToOtherMutants && otherCell->mutationId != 0
            //    && ((cell->mutationId <= otherCell->mutationId && cell->genomeComplexity <= otherCell->genomeComplexity)
            //        || static_cast<uint8_t>(cell->mutationId & 0xff) == otherCell->ancestorMutationId)) {
            //    continue;
            //}

            otherCell->detectedByCreatureId = static_cast<uint8_t>(cell->creatureId & 0xff);
        }
    }
}

__inline__ __device__ uint8_t SensorProcessor::convertAngleToData(float angle)
{
    //0 to 180 degree => 0 to 128
    //-180 to 0 degree => 128 to 256 (= 0)
    angle = remainderf(remainderf(angle, 360.0f) + 360.0f, 360.0f);  //get angle between 0 and 360
    if (angle > 180.0f) {
        angle -= 360.0f;
    }
    int result = static_cast<int>(angle * 128.0f / 180.0f);
    return static_cast<uint8_t>(result);
}

__inline__ __device__ float SensorProcessor::convertDataToAngle(uint8_t b)
{
    //0 to 127 => 0 to 179 degree
    //128 to 255 => -179 to 0 degree
    if (b < 128) {
        return (0.5f + static_cast<float>(b)) * (180.0f / 128.0f);
    } else {
        return (-256.0f - 0.5f + static_cast<float>(b)) * (180.0f / 128.0f);
    }
}
