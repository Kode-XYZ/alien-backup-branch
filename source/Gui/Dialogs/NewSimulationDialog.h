#pragma once

#include <QDialog>

#include "Model/Api/Definitions.h"
#include "Model/Api/SimulationParameters.h"

namespace Ui {
class NewSimulationDialog;
}

class SimulationParametersDialog;
class SymbolTableDialog;
class NewSimulationDialog : public QDialog
{
    Q_OBJECT

public:
	NewSimulationDialog(SimulationParameters const* parameters, SymbolTable const* symbols, Serializer* serializer, QWidget* parent = nullptr);
    virtual ~NewSimulationDialog();

    IntVector2D getUniverseSize() const;
	IntVector2D getGridSize() const;
	uint getMaxThreads() const;
	SymbolTable* getSymbolTable() const;
	SimulationParameters* getSimulationParameters() const;
	qreal getEnergy() const;

private:
	Q_SLOT void simulationParametersButtonClicked();
	Q_SLOT void symbolTableButtonClicked();
	Q_SLOT void updateUniverseSize();

private:
    Ui::NewSimulationDialog *ui;
	Serializer* _serializer = nullptr;

	SimulationParameters* _parameters = nullptr;
	SymbolTable* _symbolTable = nullptr;

	IntVector2D _universeSize;
	IntVector2D _gridSize;
};

