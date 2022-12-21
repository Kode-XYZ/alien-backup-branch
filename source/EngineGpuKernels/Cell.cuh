#pragma once

#include "EngineInterface/Constants.h"
#include "EngineInterface/Enums.h"

#include "Base.cuh"

struct CellMetadataDescription
{
    uint64_t nameSize;
    uint8_t* name;

    uint64_t descriptionSize;
    uint8_t* description;
};

struct CellConnection
{
    Cell* cell;
    float distance;
    float angleFromPrevious;
};

struct Activity
{
    float channels[MAX_CHANNELS];
};

struct NeuronFunction
{
    struct NeuronState
    {
        float weights[MAX_CHANNELS * MAX_CHANNELS];
        float bias[MAX_CHANNELS];
    };

    NeuronState* neuronState;
};

struct TransmitterFunction
{
    Enums::EnergyDistributionMode mode;
};

struct ConstructorFunction
{
    //settings
    int activationMode;  //0 = manual, 1 = every cycle, 2 = every second cycle, 3 = every third cycle, etc.
    bool singleConstruction;
    bool separateConstruction;
    bool adaptMaxConnections;
    Enums::ConstructorAngleAlignment angleAlignment;
    float stiffness;
    int constructionActivationTime;

    //genome
    uint64_t genomeSize;
    uint8_t* genome;

    //process data
    uint64_t currentGenomePos;
};

struct SensorFunction
{
    Enums::SensorMode mode;
    float angle;
    float minDensity;
    int color;
};

struct NerveFunction
{
    int pulseMode;        //0 = none, 1 = every cycle, 2 = every second cycle, 3 = every third cycle, etc.
    int alternationMode;  //0 = none, 1 = alternate after each pulse, 2 = alternate after second pulse, 3 = alternate after third pulse, etc.
};

struct AttackerFunction
{
    Enums::EnergyDistributionMode mode;
};

struct InjectorFunction
{
    uint64_t genomeSize;
    uint8_t* genome;
};

struct MuscleFunction
{
    Enums::MuscleMode mode;
};

struct PlaceHolderFunction1
{};

struct PlaceHolderFunction2
{};

union CellFunctionData
{
    NeuronFunction neuron;
    TransmitterFunction transmitter;
    ConstructorFunction constructor;
    SensorFunction sensor;
    NerveFunction nerve;
    AttackerFunction attacker;
    InjectorFunction injector;
    MuscleFunction muscle;
    PlaceHolderFunction1 placeHolder1;
    PlaceHolderFunction2 placeHolder2;
};

struct Cell
{
    uint64_t id;

    //general
    CellConnection connections[MAX_CELL_BONDS];
    float2 absPos;
    float2 vel;
    int maxConnections;
    int numConnections;
    float energy;
    float stiffness;
    int color;
    bool barrier;
    int age;

    //cell function
    Enums::LivingState livingState;
    int executionOrderNumber;
    bool inputBlocked;
    bool outputBlocked;
    Enums::CellFunction cellFunction;
    CellFunctionData cellFunctionData;
    Activity activity;
    int activationTime;

    CellMetadataDescription metadata;

    //editing data
    int selected;   //0 = no, 1 = selected, 2 = cluster selected

    //temporary data for algorithms
    int activityFetched; //0 = no, 1 = yes
    int locked;	//0 = unlocked, 1 = locked
    int tag;
    float2 temp1;
    float2 temp2;
    Cell* nextCell;

    //cluster data
    int clusterIndex;
    int clusterBoundaries;    //1 = cluster occupies left boundary, 2 = cluster occupies upper boundary
    float2 clusterPos;
    float2 clusterVel;
    float clusterAngularMomentum;
    float clusterAngularMass;
    int numCellsInCluster;

    __device__ __inline__ bool isActive()
    {
        for (int i = 0; i < MAX_CHANNELS; ++i) {
            if (abs(activity.channels[i]) > NEAR_ZERO) {
                return true;
            }
        }
        return false;
    }

    __device__ __inline__ bool isDeleted() const { return abs(energy) < NEAR_ZERO; }

    __device__ __inline__ void setDeleted()
    {
        energy = 0;
    }

    __device__ __inline__ void getLock()
    {
        while (1 == atomicExch(&locked, 1)) {}
    }

    __device__ __inline__ bool tryLock()
    {
        auto result = 0 == atomicExch(&locked, 1);
        if (result) {
            __threadfence();
        }
        return result;
    }

    __device__ __inline__ void releaseLock()
    {
        __threadfence();
        atomicExch(&locked, 0);
    }
};

template<>
struct HashFunctor<Cell*>
{
    __device__ __inline__ int operator()(Cell* const& cell)
    {
        return abs(static_cast<int>(cell->id));
    }
};

