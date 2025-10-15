# Simple Asset Placer - Architecture Documentation

## Asset Selection and Placement Flow

This flowchart shows the detailed flow when selecting an asset from the browser and performing basic operations like moving, rotating, and placing.

```mermaid
flowchart TD
    Start([User clicks asset in Asset Browser]) --> BrowserClick[AssetThumbnailItem._on_item_selected]
    
    BrowserClick --> CheckType{Asset Type?}
    
    CheckType -->|3D Model| ModelLib[ModelLibraryBrowser._on_asset_item_selected]
    CheckType -->|MeshLib Item| MeshLib[MeshLibraryBrowser._on_meshlib_item_selected]
    
    ModelLib --> DockSignal1[AssetPlacerDock._on_asset_selected]
    MeshLib --> DockSignal2[AssetPlacerDock._on_meshlib_item_selected]
    
    DockSignal1 --> LoadResource[Load Resource from Path]
    DockSignal2 --> LoadMeshLib[Get Mesh from MeshLibrary]
    
    LoadResource --> MarkUsed[CategoryManager.mark_as_used]
    LoadMeshLib --> MarkUsed
    
    MarkUsed --> EmitSignal[Emit asset_selected / meshlib_item_selected signal]
    
    EmitSignal --> PluginReceive[SimpleAssetPlacer._on_asset_selected]
    
    PluginReceive --> UpdateSettings[SettingsManager.update_dock_settings]
    
    UpdateSettings --> StartPlacement[TransformationCoordinator.start_placement_mode]
    
    StartPlacement --> ExitPrevious[Exit any previous mode]
    
    ExitPrevious --> Transition[ModeStateMachine.transition_to_mode PLACEMENT]
    
    Transition --> CreateSession[TransformSession.begin]
    
    CreateSession --> InitState[Initialize TransformState<br/>- position/target_position = Vector3.ZERO<br/>- base_height = 0.0, height_offset = 0.0<br/>- manual_rotation_offset = Vector3.ZERO<br/>- scale_multiplier = 1.0, non_uniform_multiplier = Vector3.ONE<br/>- snap settings copied from dock]
    
    InitState --> EnterHandler[PlacementModeHandler.enter_placement_mode]
    
    EnterHandler --> InitOverlays[OverlayManager.initialize_overlays<br/>OverlayManager.set_mode PLACEMENT]
    
    InitOverlays --> CreatePreview[PreviewManager.start_preview_mesh/asset]
    
    CreatePreview --> InstantiateAsset{Asset Type?}
    
    InstantiateAsset -->|PackedScene| InstScene[Instantiate PackedScene preview]
    InstantiateAsset -->|Mesh| CreateMesh[Create MeshInstance3D preview]

    InstScene --> ApplyTransparency[PreviewManager applies transparency via GeometryInstance3D.transparency]
    CreateMesh --> ApplyTransparency

    ApplyTransparency --> AddToScene[Add preview node to edited scene root]

    AddToScene --> SetInitialTransform[Initialize preview transform from TransformState<br/>- global_position = Vector3.ZERO<br/>- rotation = Vector3.ZERO<br/>- scale = Vector3.ONE]

    SetInitialTransform --> ConfigureManagers[Configure Managers with dock settings:<br/>- PositionManager.configure()<br/>- RotationManager.configure()<br/>- ScaleManager.configure()<br/>- SmoothTransformManager.configure()]
    
    ConfigureManagers --> GrabFocus[Grab 3D viewport focus]
    
    GrabFocus --> PlacementActive[PLACEMENT MODE ACTIVE]
    
    PlacementActive --> FrameLoop{Every Frame:<br/>SimpleAssetPlacer._process}
    
    FrameLoop --> GetCamera[Get active 3D camera]
    
    GetCamera --> ProcessFrame[TransformationCoordinator.process_frame_input<br/>- camera<br/>- combined settings<br/>- delta]
    
    ProcessFrame --> Orchestrator[FrameInputOrchestrator.process]
    
    Orchestrator --> UpdateInputState[InputHandler.update_input_state<br/>- Mouse position<br/>- Key states<br/>- Modifiers CTRL/ALT/SHIFT]
    
    UpdateInputState --> GetInputStates[InputHandler.get_*_input:<br/>- position_input<br/>- rotation_input<br/>- scale_input<br/>- control_mode_input<br/>- numeric_input]
    
    GetInputStates --> RouterProcess[TransformActionRouter.process]
    
    RouterProcess --> CheckModal{Modal Control<br/>Active? G/R/L}
    
    CheckModal -->|Yes - Position G| ModalPosition[Handle Position Modal:<br/>- Calculate constrained position<br/>- Apply grid snap if enabled<br/>- Update TransformState.position<br/>- Update preview position]
    
    CheckModal -->|Yes - Rotation R| ModalRotation[Handle Rotation Modal:<br/>- Process mouse delta for rotation<br/>- Apply snapping if enabled<br/>- Update manual_rotation_offset<br/>- Update preview rotation]
    
    CheckModal -->|Yes - Scale L| ModalScale[Handle Scale Modal:<br/>- Process mouse delta for scale<br/>- Apply modifiers fine/large<br/>- Update scale_multiplier<br/>- Update preview scale]
    
    CheckModal -->|No| NormalInput[Process Normal Input]
    
    ModalPosition --> UpdatePreview1[Update Preview Transform]
    ModalRotation --> UpdatePreview1
    ModalScale --> UpdatePreview1
    
    NormalInput --> MouseMove[Mouse Movement:<br/>PositionManager.update_position_from_mouse]
    
    MouseMove --> Raycast[PlacementStrategyService:<br/>- Create ray from camera through mouse<br/>- Cast ray against scene geometry<br/>- Exclude preview mesh from collision]
    
    Raycast --> CheckHit{Ray Hit?}
    
    CheckHit -->|Yes| CalculatePos[Calculate position:<br/>- Hit point + height offset<br/>- Apply grid snap if enabled<br/>- Update TransformState.position]
    
    CheckHit -->|No| KeepCurrent[Keep current position]
    
    CalculatePos --> CheckAlignment{Align with<br/>Normal?}
    
    CheckAlignment -->|Yes| AlignRotation[RotationManager.align_with_surface_normal<br/>- Calculate basis from surface normal<br/>- Update surface_alignment_rotation]
    
    CheckAlignment -->|No| ManualRotation[Use manual rotation only]
    
    AlignRotation --> CombineRotation[Combined Rotation:<br/>surface_alignment + manual_offset]
    ManualRotation --> CombineRotation
    
    KeepCurrent --> CombineRotation
    
    CombineRotation --> CheckKeys{Key Input?}
    
    CheckKeys -->|Q/E Keys| RotateY[RotationManager.rotate_y:<br/>- Add/subtract rotation step<br/>- Apply modifiers CTRL fine/ALT large<br/>- Update manual_rotation_offset.y]
    
    CheckKeys -->|X/Y/Z Keys| RotateAxis[RotationManager.rotate_axis:<br/>- Rotate around specified axis<br/>- Apply rotation step with modifiers<br/>- Update corresponding offset]
    
    CheckKeys -->|Mouse Wheel| MouseWheelRot[Fine rotation control:<br/>- Small incremental rotation<br/>- Apply to current axis]
    
    CheckKeys -->|W/A/S/D Keys| ManualMove[Camera-relative movement:<br/>- Calculate movement vector<br/>- Apply to position<br/>- Update TransformState.position]
    
    CheckKeys -->|Page Up/Down| ScaleChange[ScaleManager.adjust_scale:<br/>- Multiply scale by increment<br/>- Apply modifiers CTRL/ALT<br/>- Update scale_multiplier]
    
    CheckKeys -->|"[ / ]" Keys| CycleAsset[Cycle to next/previous asset:<br/>- Get visible items from browser<br/>- Find current selection<br/>- Select next/previous with wrap-around<br/>- Trigger new asset selection]
    
    RotateY --> SmoothTransform
    RotateAxis --> SmoothTransform
    MouseWheelRot --> SmoothTransform
    ManualMove --> SmoothTransform
    ScaleChange --> SmoothTransform
    CycleAsset --> NewAsset[Load new asset, restart flow]
    
    CheckKeys -->|No Keys| SmoothTransform[SmoothTransformManager.update_smooth_transforms<br/>- Interpolate position/rotation/scale<br/>- Respect smooth_transforms setting]
    
    SmoothTransform --> UpdatePreviewMesh[PreviewManager.update_preview_transform<br/>- position = TransformState.get_final_position()<br/>- rotation = surface_alignment + manual offset<br/>- scale = non_uniform_multiplier]
    
    UpdatePreviewMesh --> UpdateOverlay[Update Overlay Display:<br/>- Show current position<br/>- Show rotation degrees<br/>- Show scale values<br/>- Show active keybinds]
    
    UpdateOverlay --> UpdatePreview1
    
    UpdatePreview1 --> CheckPlace{Left Click<br/>or Confirm?}
    
    CheckPlace -->|Yes| PlaceAsset[PlacementModeHandler.place_at_current_position]
    CheckPlace -->|No| CheckExit{ESC or<br/>Exit Mode?}
    
    PlaceAsset --> LoadFinalAsset[UtilityManager.place_*_in_scene:<br/>- Instantiate PackedScene/Mesh<br/>- Ensure unique node name]

    LoadFinalAsset --> ApplyFinalTransform[SmoothTransformManager.apply_transform_immediately<br/>- Position from TransformState.get_final_position()<br/>- Rotation combines surface/manual offsets<br/>- Scale uses scale_multiplier]

    ApplyFinalTransform --> AddToSceneTree[Node added under edited scene root<br/>- Owner assigned for saving]

    AddToSceneTree --> CreateUndo[UndoRedoHelper.create_placement_undo<br/>- Action: Remove node<br/>- Undo: Re-add node]
    
    CreateUndo --> UpdateOverlay2[Update overlay with placement count]
    
    UpdateOverlay2 --> ContinuePlacement[Continue Placement Mode<br/>Preview still active]
    
    ContinuePlacement --> FrameLoop
    
    CheckExit -->|Yes| ExitPlacement[Exit Placement Mode]
    CheckExit -->|No| FrameLoop
    
    ExitPlacement --> CleanupPreview[PreviewManager.cleanup_preview:<br/>- Remove preview node from scene<br/>- Free node from memory]
    
    CleanupPreview --> ResetTransforms[Reset transforms if configured:<br/>- Reset height if enabled<br/>- Reset position if enabled]
    
    ResetTransforms --> HideOverlay[OverlayManager.hide_transform_overlay<br/>Remove grid overlay]
    
    HideOverlay --> ClearMode[ModeStateMachine.clear_mode<br/>TransformSession.reset]
    
    ClearMode --> End([IDLE - Ready for next asset])
    
    style PlacementActive fill:#4CAF50,stroke:#2E7D32,stroke-width:3px,color:#fff
    style UpdatePreviewMesh fill:#2196F3,stroke:#1565C0,stroke-width:2px,color:#fff
    style PlaceAsset fill:#FF9800,stroke:#E65100,stroke-width:3px,color:#fff
    style Raycast fill:#9C27B0,stroke:#6A1B9A,stroke-width:2px,color:#fff
    style RouterProcess fill:#F44336,stroke:#C62828,stroke-width:2px,color:#fff
    style FrameLoop fill:#00BCD4,stroke:#006064,stroke-width:2px,color:#fff
```

## Complete UML Class Diagram

This comprehensive diagram shows all major classes, their relationships, and the complete plugin architecture.

```mermaid
classDiagram
    %% ========================================
    %% MAIN PLUGIN ENTRY POINT
    %% ========================================
    class SimpleAssetPlacer {
        <<EditorPlugin>>
        -ServiceRegistry service_registry
        -AssetPlacerDock dock
        -Control toolbar_buttons
        -EditorUndoRedoManager undo_redo
        +_enter_tree()
        +_exit_tree()
        +_forward_3d_gui_input()
        +_input()
        +handles() bool
        -_initialize_systems()
        -_cleanup_systems()
        -_on_asset_selected()
        -_on_meshlib_item_selected()
    }

    %% ========================================
    %% SERVICE REGISTRY - DEPENDENCY INJECTION
    %% ========================================
    class ServiceRegistry {
        <<RefCounted>>
        +EditorFacade editor_facade
        +TransformationCoordinator transformation_coordinator
        +ModeStateMachine mode_state_machine
        +ControlModeState control_mode_state
        +PositionManager position_manager
        +RotationManager rotation_manager
        +ScaleManager scale_manager
        +PreviewManager preview_manager
        +OverlayManager overlay_manager
        +InputHandler input_handler
        +GridManager grid_manager
        +NumericInputManager numeric_input_manager
        +NumericInputController numeric_input_controller
        +SmoothTransformManager smooth_transform_manager
        +PlacementStrategyService placement_strategy_service
        +TransformActionRouter transform_action_router
        +UtilityManager utility_manager
        +CategoryManager category_manager
        +UndoRedoHelper undo_redo_helper
        +PlacementModeHandler placement_mode_handler
        +TransformModeHandler transform_mode_handler
        +validate() bool
        +cleanup()
    }

    %% ========================================
    %% UI COMPONENTS
    %% ========================================
    class AssetPlacerDock {
        <<Control>>
        -TabContainer tab_container
        -ModelLibraryBrowser modellib_browser
        -MeshLibraryBrowser meshlib_browser
        -PlacementSettings placement_settings
        -CategoryManager category_manager
        -ServiceRegistry _services
        +asset_selected Signal
        +meshlib_item_selected Signal
        +setup_ui()
        +discover_assets()
        +cycle_next_asset() bool
        +cycle_previous_asset() bool
        -_on_asset_selected()
        -_on_meshlib_item_selected()
    }

    class ModelLibraryBrowser {
        <<Control>>
        -GridContainer items_grid
        -ScrollContainer scroll_container
        -OptionButton category_filter
        -OptionButton filter_options
        -Array discovered_assets
        -AssetThumbnailItem selected_item
        -CategoryManager category_manager
        +asset_item_selected Signal
        +discover_assets()
        +update_asset_grid()
        +get_filtered_assets() Array
        +populate_category_filter()
        +cycle_to_next_asset() bool
        +cycle_to_previous_asset() bool
        -_on_asset_item_selected()
        -_on_context_menu_requested()
        -_scroll_to_item()
    }

    class MeshLibraryBrowser {
        <<Control>>
        -GridContainer items_grid
        -ScrollContainer scroll_container
        -OptionButton category_filter
        -OptionButton meshlib_option
        -MeshLibrary current_meshlib
        -Array meshlib_items_data
        -CategoryManager category_manager
        +meshlib_item_selected Signal
        +populate_meshlib_options()
        +populate_meshlib_items()
        +populate_category_filter()
        +cycle_to_next_item() bool
        +cycle_to_previous_item() bool
        -_on_meshlib_item_selected()
        -_on_category_filter_changed()
    }

    class AssetThumbnailItem {
        <<Button>>
        -MeshLibrary meshlib
        -int item_id
        -Dictionary asset_info
        -bool is_meshlib_item
        -TextureRect thumbnail_rect
        -Label label
        -NinePatchRect selection_border
        -CategoryManager category_manager
        +thumbnail_item_selected Signal
        +asset_item_selected Signal
        +context_menu_requested Signal
        +set_selected()
        +get_asset_path() String
        +get_asset_info() Dictionary
        +get_item_id() int
        -_gui_input()
        -_on_item_selected()
    }

    class PlacementSettings {
        <<Control>>
        -VBoxContainer settings_container
        -Array setting_controls
        +settings_changed Signal
        +get_placement_settings() Dictionary
        +save_settings()
        +load_settings()
        -_create_setting_controls()
        -_on_setting_changed()
    }

    class ToolbarButtons {
        <<Control>>
        -Button transform_mode_button
        -PlacementSettings placement_settings_ref
        -ServiceRegistry _services
        +set_services()
        +set_transform_mode_active()
        +update_strategy_button()
        -_on_transform_mode_pressed()
        -_on_cycle_strategy_pressed()
    }

    class StatusOverlayControl {
        <<Control>>
        -Label mode_label
        -Label position_label
        -Label rotation_label
        -Label scale_label
        -Label keybinds_label
        -PlacementStrategyService _placement_service
        +set_placement_strategy_service()
        +show_overlay()
        +hide_overlay()
        +update_overlay()
        +set_mode()
    }

    class TagManagementDialog {
        <<Window>>
        -Tree asset_tree
        -ItemList tag_list
        -LineEdit search_line_edit
        -CategoryManager category_manager
        -Array all_assets
        +tags_modified Signal
        +setup()
        -_populate_asset_tree()
        -_populate_tag_list()
        -_on_assign_tag()
        -_on_remove_tag()
    }

    %% ========================================
    %% CORE COORDINATION
    %% ========================================
    class TransformationCoordinator {
        <<RefCounted>>
        -ServiceRegistry _services
        -TransformSession _transform_session
        -FrameInputOrchestrator _frame_orchestrator
        -PlacementStrategyService _placement_service
        +start_placement_mode()
        +start_transform_mode()
        +exit_placement_mode()
        +exit_transform_mode()
        +exit_any_mode()
        +process_frame_input()
        +is_placement_mode() bool
        +is_transform_mode() bool
        +is_any_mode_active() bool
        +handle_mouse_wheel_input() bool
        -_grab_3d_viewport_focus()
        -_ensure_undo_redo()
    }

    class TransformSession {
        <<RefCounted>>
        +TransformState transform_state
        +Mode current_mode
        +Dictionary settings
        +Dictionary placement_data
        +Dictionary transform_data
        +Callable placement_end_callback
        +Variant dock_reference
        +int focus_grab_frames
        +begin()
        +reset()
        +is_active() bool
    }

    class TransformState {
        <<RefCounted>>
        +Vector3 position
        +Vector3 target_position
        +float base_height
        +float height_offset
        +Vector3 manual_position_offset
        +bool is_initial_position
        +Vector2 last_raycast_xz
        +Vector3 manual_rotation_offset
        +Vector3 surface_alignment_rotation
        +Vector3 surface_normal
        +float scale_multiplier
        +Vector3 non_uniform_multiplier
        +bool snap_enabled
        +float snap_step
        +Vector3 snap_offset
        +bool snap_y_enabled
        +float snap_y_step
        +bool snap_center_x
        +bool snap_center_y
        +bool snap_center_z
        +bool use_half_step
        +bool snap_rotation_enabled
        +float snap_rotation_step
        +bool snap_scale_enabled
        +float snap_scale_step
        +bool align_with_normal
        +int collision_mask
        +float height_step_size
        +reset_all()
        +reset_position()
        +reset_all_rotation()
        +reset_scale()
        +configure_from_settings()
        +set_scale_multiplier()
        +set_non_uniform_scale()
        +reset_for_new_placement()
        +get_final_position() Vector3
        +get_final_rotation() Vector3
        +get_final_rotation_degrees() Vector3
        +get_scale_vector() Vector3
        +to_dictionary() Dictionary
        +from_dictionary()
    }

    class FrameInputOrchestrator {
        <<RefCounted>>
        -ServiceRegistry _services
        -TransformationCoordinator _owner
        +process()
    }

    %% ========================================
    %% MODE MANAGEMENT
    %% ========================================
    class ModeStateMachine {
        <<RefCounted>>
        -Mode _current_mode
        -ServiceRegistry _services
        +transition_to_mode() bool
        +clear_mode()
        +get_current_mode() Mode
        +is_placement_mode() bool
        +is_transform_mode() bool
        +is_any_mode_active() bool
        -_can_transition() bool
    }

    class Mode {
        <<enumeration>>
        IDLE
        PLACEMENT
        TRANSFORM
    }

    class PlacementModeHandler {
        <<RefCounted>>
        -ServiceRegistry _services
        +enter_placement_mode() Dictionary
        +exit_placement_mode()
        +process_input()
        +place_at_current_position()
        +process_asset_cycling_input()
        +update_overlays()
        -_process_height_input()
        -_apply_numeric_input()
        -_handle_position_modal()
        -_handle_rotation_modal()
        -_handle_scale_modal()
        -_process_mouse_rotation()
        -_process_mouse_scale()
        -_calculate_constrained_position()
        -_reset_transforms_on_exit()
    }

    class TransformModeHandler {
        <<RefCounted>>
        -ServiceRegistry _services
        +enter_transform_mode() Dictionary
        +exit_transform_mode()
        +process_input()
        +confirm_transform()
        +cancel_transform()
        -_calculate_group_aabb()
        -_process_group_transform()
        -_store_original_transforms()
        -_restore_original_transforms()
        -_apply_transforms_to_nodes()
    }

    class ControlModeState {
        <<RefCounted>>
        -ControlMode _current_control_mode
        -bool _modal_active
        -Dictionary _axis_constraints
        -Vector3 _constraint_origin
        -bool _has_constraint_origin
        +switch_to_position_mode()
        +switch_to_rotation_mode()
        +switch_to_scale_mode()
        +process_axis_key_press()
        +clear_all_axis_constraints()
        +has_axis_constraint() bool
        +get_axis_constraint_string() String
        +is_modal_active() bool
        +is_position_mode() bool
        +is_rotation_mode() bool
        +is_scale_mode() bool
        +deactivate_modal()
        +reset()
    }

    class ControlMode {
        <<enumeration>>
        POSITION
        ROTATION
        SCALE
    }

    %% ========================================
    %% TRANSFORM MANAGERS (Stateless)
    %% ========================================
    class PositionManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -PlacementStrategyService _placement_service
        -float _height_step_size
        -int _collision_mask
        +update_position_from_mouse() Vector3
        +adjust_height()
        +adjust_height_with_modifiers()
        +reset_height()
        +move_direction_with_modifiers()
        +reset_position()
        +reset_for_new_placement()
        +set_use_half_step()
        +get_current_position() Vector3
        +get_surface_normal() Vector3
        +configure()
        +get_configuration() Dictionary
        -_apply_grid_snap()
        -_calculate_position()
    }

    class RotationManager {
        <<RefCounted>>
        -ServiceRegistry _services
        +set_rotation_offset()
        +set_rotation_offset_degrees()
        +get_rotation_offset() Vector3
        +get_rotation_offset_degrees() Vector3
        +get_current_rotation() Vector3
        +rotate_x()
        +rotate_y()
        +rotate_z()
        +rotate_axis()
        +rotate_axis_with_modifiers()
        +align_with_surface_normal()
        +reset_rotation()
        +reset_surface_alignment()
        +reset_all_rotation()
        +configure()
        -_normalize_rotation()
    }

    class ScaleManager {
        <<RefCounted>>
        -ServiceRegistry _services
        +set_scale_multiplier()
        +get_scale_multiplier() Vector3
        +get_final_scale() Vector3
        +scale_up()
        +scale_down()
        +adjust_scale()
        +adjust_scale_with_modifiers()
        +reset_scale()
        +configure()
    }

    class PreviewManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -Node3D _preview_mesh
        -StandardMaterial3D _preview_material
        -Vector3 _current_position
        -Vector3 _current_rotation
        -Vector3 _current_scale
        -float _preview_opacity
        -Color _preview_color
        +start_preview_mesh()
        +start_preview_asset()
        +update_preview_position()
        +update_preview_rotation()
        +update_preview_scale()
        +update_preview_transform()
        +cleanup_preview()
        +has_preview() bool
        +get_preview_mesh() Node3D
        +get_preview_position() Vector3
        +get_preview_rotation() Vector3
        +get_preview_scale() Vector3
        +set_preview_visibility()
        +set_preview_opacity()
        +set_preview_color()
        +configure()
        -_apply_preview_transparency_to_children()
    }

    class SmoothTransformManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -Dictionary _tracked_objects
        -bool _smooth_enabled
        -float _smooth_speed
        +register_object()
        +unregister_object()
        +set_target_position()
        +set_target_rotation()
        +set_target_scale()
        +set_target_transform()
        +update_smooth_transforms()
        +is_object_registered() bool
        +configure()
    }

    class GridManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -Vector3 _last_snapped_position
        +reset_tracking()
        +get_snap_step() float
        +get_snap_y_step() float
        +is_snap_enabled() bool
        +is_snap_y_enabled() bool
    }

    class OverlayManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -StatusOverlayControl _status_overlay
        -Control _grid_overlay
        +initialize_overlays()
        +show_transform_overlay()
        +hide_transform_overlay()
        +update_overlay()
        +set_mode()
        +create_grid_overlay()
        +remove_grid_overlay()
        +is_overlay_visible() bool
    }

    class UtilityManager {
        <<RefCounted>>
        -ServiceRegistry _services
        +place_asset_in_scene() Node
        +get_mesh_from_scene() Mesh
        -_apply_transform_to_instance()
        -_find_mesh_in_children()
    }

    %% ========================================
    %% INPUT SYSTEM
    %% ========================================
    class InputHandler {
        <<RefCounted>>
        -ServiceRegistry _services
        -Dictionary _current_settings
        -Vector2 _mouse_position
        -Dictionary _key_states
        +update_input_state()
        +get_position_input() PositionInputState
        +get_rotation_input() RotationInputState
        +get_scale_input() ScaleInputState
        +get_control_mode_input() ControlModeInputState
        +get_numeric_input() NumericInputState
        +get_modifier_state() Dictionary
        +is_fine_increment_modifier_held() bool
        +is_large_increment_modifier_held() bool
        +is_key_pressed() bool
        -_check_key_binding()
    }

    class TransformActionRouter {
        <<RefCounted>>
        -ServiceRegistry _services
        +process() Dictionary
        -_handle_control_mode_input()
        -_dispatch_modal_callbacks()
        -_invoke_callback()
    }

    class NumericInputController {
        <<RefCounted>>
        -ServiceRegistry _services
        -NumericInputManager _numeric_manager
        -String _last_action_type
        -String _last_action_axis
        +track_action_context()
        +process_numeric_input()
        +is_active() bool
        +is_confirmed() bool
        +confirm_action()
        +reset()
        +get_current_input_type() String
        +get_current_axis() String
    }

    class NumericInputManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -String _buffer
        -String _active_axis
        -String _input_type
        -bool _active
        +start_input()
        +append_digit()
        +append_decimal()
        +append_minus()
        +backspace()
        +clear()
        +get_numeric_value() float
        +is_active() bool
        +get_buffer() String
        +reset()
    }

    class PositionInputState {
        <<RefCounted>>
        +Vector2 mouse_position
        +bool confirm_action
        +bool cancel_action
        +bool fine_increment_modifier_held
        +bool large_increment_modifier_held
        +bool height_up
        +bool height_down
        +bool move_forward
        +bool move_backward
        +bool move_left
        +bool move_right
    }

    class RotationInputState {
        <<RefCounted>>
        +bool rotate_y_positive
        +bool rotate_y_negative
        +bool rotate_x_positive
        +bool rotate_x_negative
        +bool rotate_z_positive
        +bool rotate_z_negative
        +bool wheel_up
        +bool wheel_down
    }

    class ScaleInputState {
        <<RefCounted>>
        +bool scale_up
        +bool scale_down
    }

    class ControlModeInputState {
        <<RefCounted>>
        +bool position_control_pressed
        +bool rotation_control_pressed
        +bool scale_control_pressed
        +bool axis_x_pressed
        +bool axis_y_pressed
        +bool axis_z_pressed
    }

    class NumericInputState {
        <<RefCounted>>
        +Array digit_keys_pressed
        +bool decimal_pressed
        +bool minus_pressed
        +bool backspace_pressed
    }

    %% ========================================
    %% PLACEMENT STRATEGY SYSTEM
    %% ========================================
    class PlacementStrategyService {
        <<RefCounted>>
        -CollisionPlacementStrategy _collision_strategy
        -PlanePlacementStrategy _plane_strategy
        -PlacementStrategy _active_strategy
        -String _active_strategy_type
        -Dictionary _config
        +initialize()
        +cleanup()
        +set_strategy() bool
        +get_active_strategy_type() String
        +get_active_strategy_name() String
        +cycle_strategy() String
        +configure()
        +calculate_position() PlacementResult
        +calculate_position_with_strategy() PlacementResult
        +get_available_strategies() Array
        +get_strategy_info() Dictionary
        +reset_all_strategies()
        +get_collision_strategy()
        +get_plane_strategy()
        +get_active_strategy()
    }

    class PlacementStrategyManager {
        <<RefCounted - Static>>
        -PlacementStrategyService _service
        +set_service()
        +initialize()
        +cleanup()
        +set_strategy() bool
        +get_active_strategy_type() String
        +get_active_strategy_name() String
        +cycle_strategy() String
        +configure()
        +calculate_position() PlacementResult
        +calculate_position_with_strategy() PlacementResult
        +get_collision_strategy()
        +get_plane_strategy()
        +reset_all_strategies()
        +get_available_strategies() Array
        +get_strategy_info() Dictionary
    }

    class PlacementStrategy {
        <<RefCounted>>
        +calculate_position() PlacementResult
        +get_strategy_name() String
        +get_strategy_type() String
        +configure()
        +reset()
    }

    class CollisionPlacementStrategy {
        <<PlacementStrategy>>
        -int _collision_mask
        -Array _exclude_nodes
        +calculate_position() PlacementResult
        +get_strategy_name() String
        +configure()
    }

    class PlanePlacementStrategy {
        <<PlacementStrategy>>
        -float _plane_height
        -Vector3 _plane_normal
        +calculate_position() PlacementResult
        +get_strategy_name() String
        +configure()
    }

    class PlacementResult {
        <<RefCounted>>
        +Vector3 position
        +Vector3 normal
        +bool hit_collision
        +float distance_from_camera
    }

    %% ========================================
    %% TRANSFORM UTILITIES
    %% ========================================
    class TransformApplicator {
        <<RefCounted - Static>>
        +apply_transform_state()
        +apply_position_only()
        +apply_rotation_only()
        +apply_scale_only()
        +apply_position()
        +apply_rotation()
        +apply_scale()
        +apply_grid_snap() Vector3
        +copy_transform_from_node()
        +force_apply_immediate()
        +apply_to_multiple_nodes()
    }

    %% ========================================
    %% SETTINGS SYSTEM
    %% ========================================
    class SettingsManager {
        <<RefCounted - Static>>
        -Dictionary _dock_settings
        -Dictionary _plugin_settings
        +get_combined_settings() Dictionary
        +update_dock_settings()
        +set_dock_settings()
        +get_plugin_setting()
        +set_plugin_setting()
        +get_setting_value()
        +is_plugin_key() bool
        +save_to_file()
        +load_from_file()
    }

    class SettingsDefinition {
        <<RefCounted - Static>>
        +get_all_settings() Array
        +get_setting_by_id() SettingMeta
        +get_basic_settings() Array
        +get_placement_settings() Array
        +get_transform_settings() Array
    }

    class SettingMeta {
        <<RefCounted>>
        +String id
        +String editor_key
        +Variant default_value
        +SettingType type
        +String ui_label
        +String ui_tooltip
        +float min_value
        +float max_value
        +float step
        +String section
        +Array options
    }

    class SettingType {
        <<enumeration>>
        BOOL
        FLOAT
        STRING
        VECTOR3
        KEY_BINDING
        OPTION
    }

    class SettingsPersistence {
        <<RefCounted - Static>>
        +save_to_editor_settings()
        +load_from_editor_settings()
        +get_editor_setting()
        +set_editor_setting()
    }

    class SettingsStorage {
        <<RefCounted - Static>>
        +save_to_config_file()
        +load_from_config_file()
        +get_config_path() String
    }

    class SettingsUIBuilder {
        <<RefCounted - Static>>
        +create_setting_control() Control
        +create_bool_control() CheckBox
        +create_float_control() SpinBox
        +create_key_binding_control() Button
        +create_option_control() OptionButton
    }

    class SettingsValidator {
        <<RefCounted - Static>>
        +validate_setting() bool
        +validate_key_binding() bool
        +validate_range() bool
    }

    %% ========================================
    %% CATEGORY & TAG SYSTEM
    %% ========================================
    class CategoryManager {
        <<RefCounted>>
        -ServiceRegistry _services
        -Dictionary _category_data
        -String _config_file_path
        +extract_folder_categories() Array
        +get_custom_tags() Array
        +get_all_custom_tags() Array
        +add_tag()
        +remove_tag()
        +create_tag()
        +delete_tag()
        +toggle_favorite()
        +is_favorite() bool
        +mark_as_used()
        +is_recent() bool
        +get_recent_assets() Array
        +load_config_file()
        +save_config_file()
        +cleanup_orphaned_data()
    }

    %% ========================================
    %% THUMBNAIL SYSTEM
    %% ========================================
    class ThumbnailGenerator {
        <<RefCounted - Static>>
        -Dictionary _thumbnail_cache
        -SubViewport _thumbnail_viewport
        -Camera3D _thumbnail_camera
        +initialize()
        +generate_thumbnail() Texture2D
        +generate_mesh_thumbnail() Texture2D
        +generate_scene_thumbnail() Texture2D
        +get_cached_thumbnail() Texture2D
        +clear_cache()
        +cleanup()
    }

    class ThumbnailQueueManager {
        <<RefCounted - Static>>
        -Array _queue
        -int _processing_index
        -bool _is_processing
        +queue_thumbnail_generation()
        +process_queue()
        +clear_queue()
        +is_processing() bool
    }

    class AssetScanner {
        <<RefCounted - Static>>
        +scan_directory() Array
        +get_meshlib_paths() Array
        +is_supported_extension() bool
        +get_asset_info() Dictionary
    }

    %% ========================================
    %% UTILITY CLASSES
    %% ========================================
    class EditorFacade {
        <<RefCounted>>
        -EditorInterface _editor_interface
        +get_edited_scene_root() Node
        +get_editor_viewport_3d() SubViewport3D
        +get_undo_redo() EditorUndoRedoManager
        +get_selection() EditorSelection
        +get_editor_settings() EditorSettings
    }

    class PluginLogger {
        <<RefCounted - Static>>
        +info()
        +warning()
        +error()
        +debug()
        +log()
    }

    class PluginConstants {
        <<RefCounted - Static>>
        +COMPONENT_MAIN String
        +COMPONENT_DOCK String
        +COMPONENT_TRANSFORM String
        +VERSION String
        +FOCUS_GRAB_FRAMES int
    }

    class IncrementCalculator {
        <<RefCounted - Static>>
        +calculate_position_step() float
        +calculate_rotation_step() float
        +calculate_scale_step() float
    }

    class NodeUtils {
        <<RefCounted - Static>>
        +is_valid() bool
        +is_valid_and_in_tree() bool
        +safe_set_visible()
        +cleanup_and_null() Node
        +find_node_by_type() Node
    }

    class LayoutCalculator {
        <<RefCounted - Static>>
        +calculate_grid_columns() int
        +calculate_item_size() Vector2
        +THUMBNAIL_SIZE_DEFAULT int
        +THUMBNAIL_SIZE_MIN int
        +THUMBNAIL_SIZE_MAX int
    }

    class ErrorHandler {
        <<RefCounted - Static>>
        +handle_error()
        +log_error()
        +show_error_dialog()
    }

    class UndoRedoHelper {
        <<RefCounted>>
        -ServiceRegistry _services
        +is_valid_for_undo() bool
        +is_scene_valid() bool
        +validate_undo_manager() bool
        +create_placement_undo() bool
        +create_transform_undo() bool
        +create_multi_transform_undo() bool
        +handle_undo_error()
        +get_action_description() String
        +should_create_undo() bool
    }

    %% ========================================
    %% RELATIONSHIPS
    %% ========================================
    
    %% Main plugin relationships
    SimpleAssetPlacer --> ServiceRegistry : creates & injects
    SimpleAssetPlacer --> AssetPlacerDock : creates
    SimpleAssetPlacer --> ToolbarButtons : creates
    SimpleAssetPlacer --> EditorFacade : uses
    
    %% Service Registry contains all managers
    ServiceRegistry --> TransformationCoordinator : contains
    ServiceRegistry --> ModeStateMachine : contains
    ServiceRegistry --> ControlModeState : contains
    ServiceRegistry --> PositionManager : contains
    ServiceRegistry --> RotationManager : contains
    ServiceRegistry --> ScaleManager : contains
    ServiceRegistry --> PreviewManager : contains
    ServiceRegistry --> OverlayManager : contains
    ServiceRegistry --> InputHandler : contains
    ServiceRegistry --> GridManager : contains
    ServiceRegistry --> NumericInputManager : contains
    ServiceRegistry --> NumericInputController : contains
    ServiceRegistry --> SmoothTransformManager : contains
    ServiceRegistry --> PlacementStrategyService : contains
    ServiceRegistry --> TransformActionRouter : contains
    ServiceRegistry --> UtilityManager : contains
    ServiceRegistry --> CategoryManager : contains
    ServiceRegistry --> UndoRedoHelper : contains
    ServiceRegistry --> PlacementModeHandler : contains
    ServiceRegistry --> TransformModeHandler : contains
    ServiceRegistry --> EditorFacade : contains
    
    %% UI relationships
    AssetPlacerDock --> ModelLibraryBrowser : contains
    AssetPlacerDock --> MeshLibraryBrowser : contains
    AssetPlacerDock --> PlacementSettings : contains
    AssetPlacerDock --> CategoryManager : uses
    
    ModelLibraryBrowser --> AssetThumbnailItem : creates many
    ModelLibraryBrowser --> CategoryManager : uses
    ModelLibraryBrowser --> TagManagementDialog : creates
    
    MeshLibraryBrowser --> AssetThumbnailItem : creates many
    MeshLibraryBrowser --> CategoryManager : uses
    
    PlacementSettings --> SettingsDefinition : uses
    PlacementSettings --> SettingsUIBuilder : uses
    
    ToolbarButtons --> PlacementSettings : references
    ToolbarButtons --> ServiceRegistry : uses
    
    OverlayManager --> StatusOverlayControl : manages
    StatusOverlayControl --> PlacementStrategyService : uses
    
    %% Core coordination relationships
    TransformationCoordinator --> ServiceRegistry : uses all managers
    TransformationCoordinator --> TransformSession : manages
    TransformationCoordinator --> FrameInputOrchestrator : uses
    TransformationCoordinator --> ModeStateMachine : uses
    
    TransformSession --> TransformState : contains
    
    FrameInputOrchestrator --> PlacementModeHandler : delegates to
    FrameInputOrchestrator --> TransformModeHandler : delegates to
    
    %% Mode handler relationships
    PlacementModeHandler --> ServiceRegistry : uses all managers
    PlacementModeHandler --> TransformState : operates on
    PlacementModeHandler --> TransformApplicator : uses
    
    TransformModeHandler --> ServiceRegistry : uses all managers
    TransformModeHandler --> TransformState : operates on
    TransformModeHandler --> TransformApplicator : uses
    
    ModeStateMachine --> Mode : uses enum
    ControlModeState --> ControlMode : uses enum
    
    %% Transform manager relationships
    PositionManager --> TransformState : reads/writes
    PositionManager --> PlacementStrategyService : uses
    
    RotationManager --> TransformState : reads/writes
    ScaleManager --> TransformState : reads/writes
    
    PreviewManager --> TransformState : reads from
    PreviewManager --> SmoothTransformManager : registers with
    
    TransformApplicator --> TransformState : reads from
    TransformApplicator --> GridManager : uses
    
    %% Input system relationships
    InputHandler --> PositionInputState : creates
    InputHandler --> RotationInputState : creates
    InputHandler --> ScaleInputState : creates
    InputHandler --> ControlModeInputState : creates
    InputHandler --> NumericInputState : creates
    InputHandler --> SettingsManager : uses
    
    TransformActionRouter --> InputHandler : uses
    TransformActionRouter --> ControlModeState : uses
    TransformActionRouter --> NumericInputController : uses
    
    NumericInputController --> NumericInputManager : uses
    
    %% Placement strategy relationships
    PlacementStrategyManager --> PlacementStrategyService : wraps
    PlacementStrategyManager --> PlacementStrategy : manages
    PlacementStrategy <|-- CollisionPlacementStrategy : implements
    PlacementStrategy <|-- PlanePlacementStrategy : implements
    PlacementStrategy --> PlacementResult : returns
    
    %% Settings relationships
    SettingsManager --> SettingsPersistence : uses
    SettingsManager --> SettingsStorage : uses
    SettingsManager --> SettingsDefinition : uses
    
    SettingsDefinition --> SettingMeta : contains many
    SettingsDefinition --> SettingType : uses enum
    
    PlacementSettings --> SettingsUIBuilder : uses
    PlacementSettings --> SettingsValidator : uses
    
    %% Thumbnail system relationships
    ThumbnailGenerator --> ThumbnailQueueManager : uses
    ModelLibraryBrowser --> ThumbnailGenerator : uses
    MeshLibraryBrowser --> ThumbnailGenerator : uses
    AssetPlacerDock --> AssetScanner : uses
    
    %% Utility relationships
    UtilityManager --> NodeUtils : uses
    UtilityManager --> UndoRedoHelper : uses
    PreviewManager --> NodeUtils : uses
    PlacementModeHandler --> IncrementCalculator : uses
    TransformModeHandler --> IncrementCalculator : uses
    RotationManager --> IncrementCalculator : uses
    ScaleManager --> IncrementCalculator : uses
    
    %% Category system
    ModelLibraryBrowser --> CategoryManager : uses
    MeshLibraryBrowser --> CategoryManager : uses
    AssetThumbnailItem --> CategoryManager : uses
    TagManagementDialog --> CategoryManager : uses
```

## Key Architecture Patterns

### 1. Service Registry Pattern
All managers are registered in a central `ServiceRegistry` that provides dependency injection throughout the system.

### 2. Stateless Managers
Transform managers (`PositionManager`, `RotationManager`, `ScaleManager`) are stateless and operate on `TransformState` objects passed to them.

### 3. Mode State Machine
The `ModeStateMachine` manages transitions between IDLE, PLACEMENT, and TRANSFORM modes with proper lifecycle management.

### 4. Session Management
`TransformSession` encapsulates all state for an active placement/transform operation, making it easy to reset and clean up.

### 5. Input Routing
`TransformActionRouter` routes input to appropriate handlers based on the current modal state (Position/Rotation/Scale control with G/R/L keys).

## Data Flow Summary

1. **UI → Coordinator**: Asset selection flows from browser → dock → plugin → coordinator
2. **Coordinator → Handlers**: Mode-specific handlers manage the lifecycle
3. **Handlers → Managers**: Stateless managers perform calculations
4. **Managers → State**: All results stored in `TransformState`
5. **State → Preview**: Preview mesh updated from state
6. **State → Scene**: Final placement applies state to actual scene nodes
