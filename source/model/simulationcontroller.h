#ifndef SIMULATIONCONTROLLER_H
#define SIMULATIONCONTROLLER_H

#include "definitions.h"
#include "entities/cellto.h"

#include <QObject>
#include <QVector3D>
#include <QThread>

class QTimer;

class SimulationController  : public QObject
{
    Q_OBJECT
public:
    enum class Threading {
        NO_EXTRA_THREAD, EXTRA_THREAD
    };
    SimulationController (Threading threading, QObject* parent = 0);
    SimulationController (QVector2D size, Threading threading, QObject* parent = 0);
    ~SimulationController ();

    QMap< QString, qreal > getMonitorData ();
    Grid* getGrid ();

    //universe manipulation tools
    void newUniverse (qint32 sizeX, qint32 sizeY);
    void serializeUniverse (QDataStream& stream);
    void buildUniverse (QDataStream& stream);
    qint32 getUniverseSizeX();
    qint32 getUniverseSizeY ();
    void addBlockStructure (QVector3D center, int numCellX, int numCellY, QVector3D dist, qreal energy);
    void addHexagonStructure (QVector3D center, int numLayers, qreal dist, qreal energy);
    void addRandomEnergy (qreal energy, qreal maxEnergyPerParticle);

    //selection manipulation Tools
    void serializeCell (QDataStream& stream, Cell* cell, quint64& clusterId, quint64& cellId);
    void serializeExtendedSelection (QDataStream& stream,
                                    const QList< CellCluster* >& clusters,
                                    const QList< EnergyParticle* >& es,
                                    QList< quint64 >& clusterIds,
                                    QList< quint64 >& cellIds);
    void buildCell (QDataStream& stream,                //returns a map which maps to old to the new cell and cluster ids
                    QVector3D pos,
                    CellCluster*& newCluster,
                    QMap< quint64, quint64 >& oldNewClusterIdMap,
                    QMap< quint64, quint64 >& oldNewCellIdMap,
                    bool drawToMap = true);
    void buildExtendedSelection (QDataStream& stream,   //returns a map which maps to old to the new cell and cluster ids
                                QVector3D pos,
                                QList< CellCluster* >& newClusters,
                                QList< EnergyParticle* >& newEnergyParticles,
                                QMap< quint64, quint64 >& oldNewClusterIdMap,
                                QMap< quint64, quint64 >& oldNewCellIdMap,
                                bool drawToMap = true);
public slots:
    void delSelection (QList< Cell* > cells,
                      QList< EnergyParticle* > es);
    void delExtendedSelection (QList< CellCluster* > clusters,
                         QList< EnergyParticle* > es);
public:
    void rotateExtendedSelection (qreal angle, const QList< CellCluster* >& clusters, const QList< EnergyParticle* >& es);
    void setVelocityXExtendedSelection (qreal velX, const QList< CellCluster* >& clusters, const QList< EnergyParticle* >& es);
    void setVelocityYExtendedSelection (qreal velY, const QList< CellCluster* >& clusters, const QList< EnergyParticle* >& es);
    void setAngularVelocityExtendedSelection (qreal angVel, const QList< CellCluster* >& clusters);
    QVector3D getCenterPosExtendedSelection (const QList< CellCluster* >& clusters, const QList< EnergyParticle* >& es);
    void drawToMapExtendedSelection (const QList< CellCluster* >& clusters, const QList< EnergyParticle* >& es);

    //cell/particle manipulation tools
public slots:
    void newCell (QVector3D pos);
    void newEnergyParticle (QVector3D pos);
    void updateCell (QList< Cell* > cells,
                     QList< CellTO > newCellsData,
                     bool clusterDataChanged);

    //misc
public slots:
    void setRun (bool run);
    void forceFps (int fps);
    void requestNextTimestep ();

    void updateUniverse ();

signals:
    void setRandomSeed (uint seed);
    void calcNextTimestep ();
    void cellCreated (Cell* cell);
    void energyParticleCreated (EnergyParticle* cell);
    void reclustered (QList< CellCluster* > clusters);
    void universeUpdated (Grid* grid, bool force);
    void computerCompilationReturn (bool error, int line);

protected slots:
    virtual void forceFpsTimerSlot ();
    virtual void nextTimestepCalculated ();

protected:
    QTimer* _forceFpsTimer;
    bool _run = false;
    int _fps = 0;
    bool _calculating = false;
    quint64 _frame = 0;
    int _newCellTokenAccessNumber = 0;

    Grid* _grid;
    SimulationUnit* _unit;
    QThread _thread;
};

#endif // SIMULATIONCONTROLLER_H
