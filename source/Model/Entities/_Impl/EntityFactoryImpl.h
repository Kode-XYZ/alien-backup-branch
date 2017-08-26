#ifndef CELLFACTORYIMPL_H
#define CELLFACTORYIMPL_H

#include "Model/Entities/EntityFactory.h"

class EntityFactoryImpl
	: public EntityFactory
{
public:

	virtual ~EntityFactoryImpl() = default;

	virtual CellCluster* build(ClusterChangeDescription const& desc, UnitContext* context) const override;
	virtual Cell* build(CellChangeDescription const& desc, UnitContext* context) const override;
	virtual Token* build(TokenDescription const& desc, UnitContext* context) const override;
	virtual EnergyParticle* build(ParticleChangeDescription const& desc, UnitContext* context) const override;
};

#endif // CELLFACTORYIMPL_H
