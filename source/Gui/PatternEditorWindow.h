#pragma once

#include "EngineInterface/Definitions.h"
#include "EngineInterface/SelectionShallowData.h"
#include "EngineInterface/Descriptions.h"
#include "Definitions.h"
#include "AlienWindow.h"

class _PatternEditorWindow : public _AlienWindow
{
public:
    _PatternEditorWindow(
        EditorModel const& editorModel,
        SimulationController const& simController,
        Viewport const& viewport,
        EditorControllerWeakPtr const& editorController);
    ~_PatternEditorWindow();

    bool isObjectInspectionPossible() const;
    bool isGenomeInspectionPossible() const;

    bool isCopyingPossible() const;
    void onCopy();
    bool isPastingPossible() const;
    void onPaste();
    bool isDeletingPossible() const;
    void onDelete();

private:
    void processIntern() override;

    void onOpenPattern();
    void onSavePattern();
    void onGenerateExecutionOrderNumbers();
    void onMakeSticky();
    void onRemoveStickiness();
    void onSetBarrier(bool value);
    bool colorButton(std::string id, uint32_t cellColor);
    bool hasSelectionChanged(SelectionShallowData const& selection) const;

    EditorModel _editorModel;
    SimulationController _simController;
    Viewport _viewport;
    EditorControllerWeakPtr _editorController;

    std::string _startingPath;
    float _angle = 0;
    float _angularVel = 0;
    std::optional<SelectionShallowData> _lastSelection;
    std::optional<DataDescription> _copiedSelection;
};