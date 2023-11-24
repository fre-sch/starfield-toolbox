bl_info = {
    "name": "Starfield JSON format",
    "author": "nobody",
    "version": (0, 1, 0),
    "blender": (2, 81, 6),
    "location": "File > Import-Export",
    "description": "Import-Export Starfield JSON",
    # "doc_url": "https://google.com",
    # "support": 'none',
    "category": "Import-Export",
}

import bpy
# ImportHelper is a helper class, defines filename and
# invoke() function which calls the file selector.
from bpy_extras.io_utils import (
    ImportHelper,
    ExportHelper,
    axis_conversion,
)
from bpy.props import StringProperty, BoolProperty, PointerProperty, EnumProperty
from bpy.types import Operator, Context, Gizmo, GizmoGroup, PropertyGroup, Panel
import json
from mathutils import Matrix
import math
from os.path import basename, join as pathjoin
from dataclasses import dataclass
from unittest.mock import Mock
# import MeshConverter
# import NifIO


# @dataclass
# class Options:
#     assets_folder: str
#     skeleton_register_name: str = ""
#     max_lod: int = 1
#     boneinfo_debug: bool = False
#     correct_rotation: bool = False
#     max_border: float = 0
#     use_world_origin: bool = False
#     GEO: bool = True
#     NORM: bool = True
#     VERTCOLOR: bool = True
#     WEIGHTS: bool = True
#     export_sf_mesh_hash_result: bool = True
#     meshlets_debug: bool = False
#     culldata_debug: bool = False
#     tangents_debug: bool = False
#     import_as_read_only: bool = False
#     target_collection: object = None


# def import_nif(operator, target_collection, path):
#     options = Options(
#         operator.asset_path,
#         #"D:\\Mods\\StarfieldArchiveExtract",
#         target_collection=target_collection
#     )
#     context = Mock()
#     rtn, skel, objs = NifIO.ImportNif(
#         pathjoin(options.assets_folder, "meshes", path),
#         options, context, operator)
#     return bpy.context.active_object


FLOAT_ROUND_DIGITS = 4

def f(value):
    return round(float(value), 3)


def rf(value):
    return math.radians(f(value))


def degrees_str(value):
    degrees = round(math.degrees(value), FLOAT_ROUND_DIGITS)
    if degrees < 0:
        degrees = 360 + degrees
    return str(degrees)


def obj_name(json_data):
    if json_data["Meta"]["EDID"]:
        return json_data["Meta"]["EDID"]
    return f'{json_data["Meta"]["Signature"]}:{json_data["Meta"]["FormID"]}'


def import_obj_meta(operator, json_data):
    new_obj = bpy.data.objects.new(obj_name(json_data), None)
    new_obj.empty_display_type = operator.display_object_type
    new_obj.empty_display_size = 0.5
    new_obj.show_name = operator.show_name
    StarfieldJsonPropertyGroup.from_json(new_obj, json_data)
    return new_obj


def make_rotation_matrix(x, y, z):
    rot_x = Matrix.Rotation(math.radians(x), 4, "X")
    rot_y = Matrix.Rotation(math.radians(y), 4, "Y")
    rot_z = Matrix.Rotation(math.radians(z), 4, "Z")
    return rot_z @ rot_x @ rot_y


def import_orientation(operator, orientation_json, mat_conv=None):
    offset = orientation_json["Offset"]
    mat_loc = Matrix.Translation((
        f(offset["X"]),
        f(offset["Y"]),
        f(offset["Z"]),
    ))
    rotation = orientation_json["Rotation"]
    mat_rot = make_rotation_matrix(
        f(rotation["X"]),
        f(rotation["Y"]),
        f(rotation["Z"])
    )
    if mat_conv is None:
        mat_conv = Matrix.Identity(4)
    return mat_conv @ mat_loc @ mat_rot


def export_orientation(operator: Operator, context: Context, obj):
    mat_conv = axis_conversion(
        from_forward='-Y', from_up="Z",
        to_forward='Y', to_up='Z').to_4x4()
    mat = mat_conv @ obj.matrix_world
    # mat = obj.matrix_world
    translation, rotation, scale = mat.decompose()
    # decompose rotation to euler as inverse order of
    # mat_rot = rot_z @ rot_x @ rot_y
    # in import_orientation
    rotation_euler = rotation.to_euler("YXZ")
    return {
        "Offset": {
            "X": str(round(translation.x, FLOAT_ROUND_DIGITS)),
            "Y": str(round(translation.y, FLOAT_ROUND_DIGITS)),
            "Z": str(round(translation.z, FLOAT_ROUND_DIGITS)),
        },
        "Rotation": {
            "X": degrees_str(rotation_euler.x),
            "Y": degrees_str(rotation_euler.y),
            "Z": degrees_str(rotation_euler.z),
        }
    }


def import_stmp(operator, json_data, target_collection, matrix_axis_conv=None):
    new_obj = import_obj_meta(operator, json_data)

    if matrix_axis_conv is not None:
        new_obj.matrix_world = matrix_axis_conv

    target_collection.objects.link(new_obj)

    for enam_json in json_data["ENAM"]:
        enam_obj = bpy.data.objects.new(enam_json["Meta"]["Name"], None)
        enam_obj.empty_display_type = operator.display_snap_type
        enam_obj.empty_display_size = 0.5
        enam_obj.show_name = operator.show_name
        StarfieldJsonPropertyGroup.from_json(enam_obj, enam_json)
        enam_obj.matrix_basis = import_orientation(operator, enam_json["Orientation"])
        enam_obj.parent = new_obj
        target_collection.objects.link(enam_obj)

    return new_obj


def import_refr_child(operator, json_data, target_collection, matrix_axis_conv=None):
    new_obj = import_obj_meta(operator, json_data)

    if matrix_axis_conv is not None:
        new_obj.matrix_world = matrix_axis_conv

    target_collection.objects.link(new_obj)

    # if json_data.get("MODL"):
    #     new_obj["MODL"] = json_data["MODL"]
    #     if operator.load_nifs:
    #         # nif_obj = import_nif(operator, target_collection, json_data["MODL"])
    #         # if nif_obj is not None:
    #         #     nif_obj.parent = new_obj
    #         pass

    if json_data.get("SNTP"):
        child_obj = import_stmp(operator, json_data["SNTP"], target_collection)
        child_obj.parent = new_obj

    return new_obj


def import_refr(operator, json_data, target_collection, matrix_axis_conv=None):
    new_obj = import_obj_meta(operator, json_data)

    new_obj.matrix_basis = import_orientation(operator, json_data["DATA"], matrix_axis_conv)

    target_collection.objects.link(new_obj)

    if json_data.get("NAME"):
        child_obj = import_refr_child(operator, json_data["NAME"], target_collection)
        child_obj.parent = new_obj
    return new_obj


def import_cell(operator, json_data, target_collection, matrix_axis_conv=None):
    new_obj = import_obj_meta(operator, json_data)

    if matrix_axis_conv is not None:
        new_obj.matrix_world = matrix_axis_conv

    target_collection.objects.link(new_obj)

    for item in json_data["Temporary"]:
        child_obj = import_refr(operator, item, target_collection)
        child_obj.starfield_json.refr_group = "Temporary"
        child_obj.parent = new_obj

    for item in json_data["Persistent"]:
        child_obj = import_refr(operator, item, target_collection)
        child_obj.starfield_json.refr_group = "Persistent"
        child_obj.parent = new_obj

    return new_obj


def export_cell(operator: Operator, context: Context, obj):
    data = obj.starfield_json.to_json()
    data["Persistent"] = [
        export_refr(operator, context, it)
        for it in bpy.data.objects
        if it.parent == obj
            and it.starfield_json.is_valid()
            and it.starfield_json.refr_group == "Persistent"
    ]
    data["Temporary"] = [
        export_refr(operator, context, it)
        for it in bpy.data.objects
        if it.parent == obj
            and it.starfield_json.is_valid()
            and it.starfield_json.refr_group == "Temporary"
    ]

    return data


def export_refr(operator: Operator, context: Context, obj):
    data = obj.starfield_json.to_json()
    data["DATA"] = export_orientation(operator, context, obj)
    children = [
        it
        for it in bpy.data.objects
        if it.parent == obj and it.starfield_json.is_valid()
    ]
    if len(children) == 0:
        return data
    if len(children) > 1:
        operator.report({"WARNING"}, f"single child with meta expected, got {len(children)} for {obj.name}. Exporting first child only.")
    child = children[0]
    data["NAME"] = export_refr_child(operator, context, child)
    return data


def export_refr_child(operator: Operator, context: Context, obj):
    data = obj.starfield_json.to_json()
    children = [
        it
        for it in bpy.data.objects
        if it.parent == obj and it.starfield_json.is_valid()
    ]
    if len(children) == 0:
        return data
    if len(children) > 1:
        operator.report({"WARNING"}, f"single child with meta expected, got {len(children)} for {obj.name}. Exporting first child only.")

    child_obj = children[0]
    if child_obj.starfield_json.signature == "STMP":
        data["SNTP"] = export_stmp(operator, context, child_obj)
    else:
        operator.report({"WARNING"}, f"Only `STMP` children supported for {obj.name}, got {child_obj.starfield_json.signature} for {child_obj.name}.")
    return data


def export_stmp(operator: Operator, context: Context, obj):
    data = obj.starfield_json.to_json()
    data["ENAM"] = []
    children = [
        it
        for it in bpy.data.objects
        if it.parent == obj
    ]
    if len(children) == 0:
        operator.report({"WARNING"}, f"Expected children for {obj.name}, got none.")
        return data

    for child_obj in children:
        if not child_obj.starfield_json.is_valid():
            operator.report({"WARNING"}, f"Child {child_obj.name} of {obj.name} missing starfield_json data.")
            continue
        child_data = child_obj.starfield_json.to_json()
        data["ENAM"].append({
            **child_data,
            "Orientation": export_orientation(operator, context, child_obj)
        })

    return data


def read_json_file(operator: Operator, context: Context, filepath: str):
    if operator.load_nifs and not operator.asset_path:
        operator.load_nifs = False
        operator.report({"WARNING"}, "Loading NIFs enabled, but asset path is empty. Disabling loading NIFs.")

    with open(filepath, 'r', encoding='utf-8') as fp:
        data = json.load(fp)

    if operator.as_new_collection:
        target_collection = bpy.data.collections.new(basename(filepath))
        bpy.context.scene.collection.children.link(target_collection)
    else:
        target_collection = context.view_layer.active_layer_collection.collection

    matrix_axis_conv = axis_conversion(
        from_forward='Y', from_up="Z",
        to_forward='-Y', to_up='Z').to_4x4()

    if data["Meta"]["Signature"] == "CELL":
        import_cell(operator, data, target_collection, matrix_axis_conv)

    elif data["Meta"]["Signature"] == "REFR":
        import_refr(operator, data, target_collection, matrix_axis_conv)

    elif data["Meta"]["Signature"] in "MSTT,STAT":
        import_refr_child(operator, data, target_collection, matrix_axis_conv)

    elif data["Meta"]["Signature"] == "STMP":
        import_stmp(operator, data, target_collection, matrix_axis_conv)

    else:
        operator.report({"WARNING"}, f"expected meta signature (CELL,REFR,MSTT,STAT,STMP), got `{data['Meta']['Signature']}`")
        return {"CANCELLED"}

    return {'FINISHED'}


def write_json_file(operator: Operator, context: Context, filepath: str):
    obj = context.active_object
    if not obj.starfield_json.is_valid():
        operator.report({"ERROR"}, f"selected object {obj.name} missing meta data.")
        return {"CANCELLED"}

    if obj.starfield_json.signature == "CELL":
        json_data = export_cell(operator, context, obj)
    elif obj.starfield_json.signature == "REFR":
        json_data = export_refr(operator, context, obj)
    elif obj.starfield_json.signature in ("MSTT", "STAT"):
        json_data = export_refr_child(operator, context, obj)
    elif obj.starfield_json.signature == "STMP":
        json_data = export_stmp(operator, context, obj)
    else:
        operator.report({"WARNING"}, f"expected meta signature (CELL,REFR,MSTT,STAT,STMP), got `{obj.starfield_json.signature}`")
        return {"CANCELLED"}

    with open(filepath, "w") as fp:
        json.dump(json_data, fp, indent=2)

    return {"FINISHED"}


StarfieldSnapRotations = {
    "SnapNode_SHIP_Top01 [STND:0004AB77]": (-90.0, 0.0, 0.0),
    "SnapNode_SHIP_Bottom01 [STND:0004AB78]": (90.0, 0.0, 180.0),
    "SnapNode_SHIP_Fore01 [STND:0004AB6F]": (0.0, 0.0, 0.0),
    "SnapNode_SHIP_Aft01 [STND:0004AB70]": (0.0, 0.0, 180.0),
    "SnapNode_SHIP_Port01 [STND:0004AB73]": (0.0, 0.0, -90.0),
    "SnapNode_SHIP_Starboard01 [STND:0004AB74]": (0.0, 0.0, 90.0),
    "SnapNode_SHIP_Equipment_Side01A [STND:0004AB85]": None,
    "SnapNode_SHIP_Equipment_Side01B [STND:0004AB89]": None
}

def handle_snap_name_update(self_, context):
    if self_ is None:
        return
    if context is None:
        return
    obj = context.active_object
    obj.name = f'{self_.node_id}-{self_.snap_name}'

    snap_rot = StarfieldSnapRotations.get(self_.snap_name)
    if snap_rot is None:
        return
    mat_rot = make_rotation_matrix(*snap_rot)
    mat_rot.translation = obj.matrix_world.translation
    obj.matrix_world = mat_rot


class StarfieldJsonPropertyGroup(PropertyGroup):
    signature: StringProperty(name="Signature")
    editor_id: StringProperty(name="EditorID")
    form_id: StringProperty(name="FormID")
    file_name: StringProperty(name="FileName")
    name: StringProperty(name="Name")
    refr_group : StringProperty(name="GRUP")
    model_path: StringProperty(name="Model Path")
    node_id: StringProperty(name="Node ID")
    snap_name: EnumProperty(
        name="Snap Name",
        items=[
            ("NONE", "", ""),
            ("SnapNode_SHIP_Top01 [STND:0004AB77]", "SnapNode_SHIP_Top01 [STND:0004AB77]", "TOP"),
            ("SnapNode_SHIP_Bottom01 [STND:0004AB78]", "SnapNode_SHIP_Bottom01 [STND:0004AB78]", "BTM"),
            ("SnapNode_SHIP_Fore01 [STND:0004AB6F]", "SnapNode_SHIP_Fore01 [STND:0004AB6F]", "FORE"),
            ("SnapNode_SHIP_Aft01 [STND:0004AB70]", "SnapNode_SHIP_Aft01 [STND:0004AB70]", "AFT"),
            ("SnapNode_SHIP_Port01 [STND:0004AB73]", "SnapNode_SHIP_Port01 [STND:0004AB73]", "PORT"),
            ("SnapNode_SHIP_Starboard01 [STND:0004AB74]", "SnapNode_SHIP_Starboard01 [STND:0004AB74]", "STBD"),
            ("SnapNode_SHIP_Equipment_Side01A [STND:0004AB85]", "SnapNode_SHIP_Equipment_Side01A [STND:0004AB85]", "SIDE01A"),
            ("SnapNode_SHIP_Equipment_Side01B [STND:0004AB89]", "SnapNode_SHIP_Equipment_Side01B [STND:0004AB89]", "SIDE01B"),
        ],
        options=set(),
        default="NONE",
        update=handle_snap_name_update
    )

    @classmethod
    def from_json(cls, obj, obj_json):
        obj.starfield_json.signature = obj_json["Meta"].get("Signature", "")
        obj.starfield_json.editor_id = obj_json["Meta"].get("EDID", "")
        obj.starfield_json.form_id = obj_json["Meta"].get("FormID", "")
        obj.starfield_json.file_name = obj_json["Meta"].get("FileName", "")
        obj.starfield_json.name = obj_json["Meta"].get("Name", "")
        if obj_json["Meta"].get("Signature", "") == "STMP.Node":
            obj.starfield_json.node_id = obj_json.get("Node ID", "")
            obj.starfield_json.snap_name = obj_json.get("Node", "NONE")
        obj.starfield_json.model_path = obj_json.get("MODL", "")
        # refr_group is handled separately

    def is_valid(self):
        return bool(self.signature)

    def to_json(self):
        obj_json = {"Meta": {}}
        if self.signature:
            obj_json["Meta"]["Signature"] = self.signature
        if self.editor_id:
            obj_json["Meta"]["EDID"] = self.editor_id
        if self.form_id:
            obj_json["Meta"]["FormID"] = self.form_id
        if self.file_name:
            obj_json["Meta"]["FileName"] = self.file_name
        if self.name:
            obj_json["Meta"]["Name"] = self.name
        if self.node_id:
            obj_json["Node ID"] = self.node_id
        if self.snap_name and self.snap_name != "NONE":
            obj_json["Node"] = self.snap_name
        if self.model_path:
            obj_json["MODL"] = self.model_path
        # refr_group is handled separately
        return obj_json


class StarfieldJsonPropertyGroupPanel(Panel):
    bl_label = "Starfield JSON"
    bl_space_type = "PROPERTIES"
    bl_region_type = "WINDOW"
    bl_context = "object"

    def draw(self, context):
        if context.object.starfield_json.signature == "STMP.Node":
            self.layout.row().prop(context.object.starfield_json, "node_id")
            self.layout.row().prop(context.object.starfield_json, "snap_name")
        else:
            self.layout.row().prop(context.object.starfield_json, "signature")
            self.layout.row().prop(context.object.starfield_json, "editor_id")
            self.layout.row().prop(context.object.starfield_json, "form_id")
            self.layout.row().prop(context.object.starfield_json, "file_name")
            self.layout.row().prop(context.object.starfield_json, "name")
        if context.object.starfield_json.signature in ("MSTT", "STAT"):
            self.layout.row().prop(context.object.starfield_json, "model_path")
        if context.object.starfield_json.signature == "REFR":
            self.layout.row().prop(context.object.starfield_json, "refr_group")



class StarfieldJsonImport(Operator, ImportHelper):
    bl_idname = "starfield_json.import_file"
    bl_label = "Import Starfield JSON"
    filename_ext = ".json"

    filter_glob: StringProperty(
        default="*.json",
        options={'HIDDEN'},
        maxlen=255,  # Max internal buffer length, longer would be clamped.
    )
    as_new_collection: BoolProperty(
        name="Import as new collection",
        description="Import as new collection or into current active collection",
        default=True,
    )
    display_object_type: EnumProperty(
        name="Display Objects as",
        items=[
            ("PLAIN_AXES", "Plain Axes", "Plain Axes"),
            ("ARROWS", "Arrows", "Arrows"),
            ("SINGLE_ARROW", "Single Arrow", "Single Arrow"),
            ("CIRCLE", "Circle", "Circle"),
            ("CUBE", "Cube", "Cube"),
            ("SPHERE", "Sphere", "Sphere"),
            ("CONE", "Cone", "Cone"),
        ],
        default="ARROWS"
    )
    display_snap_type: EnumProperty(
        name="Display Snaps as",
        items=[
            ("PLAIN_AXES", "Plain Axes", "Plain Axes"),
            ("ARROWS", "Arrows", "Arrows"),
            ("SINGLE_ARROW", "Single Arrow", "Single Arrow"),
            ("CIRCLE", "Circle", "Circle"),
            ("CUBE", "Cube", "Cube"),
            ("SPHERE", "Sphere", "Sphere"),
            ("CONE", "Cone", "Cone"),
        ],
        default="CIRCLE"
    )
    show_name: BoolProperty(
        name="Show names",
        default=False
    )
    load_nifs: BoolProperty(
        name="EXPERIMENTAL: Load NIFs",
        description="WARNING: loading NIFs is experimental and extremely slow",
        default=False,
    )
    asset_path: StringProperty(
        name="EXPERIMENTAL: Asset path for loading NIFs",
        description="WARNING: loading NIFs is experimental and potentially extremely slow",
        default="",
    )

    def execute(self, context: Context):
        return read_json_file(self, context, self.filepath)


class StarfieldJsonExport(Operator, ExportHelper):
    bl_idname = "starfield_json.export_file"
    bl_label = "Export Starfield JSON"
    filename_ext = ".json"

    filter_glob: StringProperty(
        default="*.json",
        options={'HIDDEN'}
    )

    def invoke(self, context, _event):
        self.filepath = f"{context.active_object.name}.json"
        return super().invoke(context, _event)

    def execute(self, context: Context):
        return write_json_file(self, context, self.filepath)


SnapGizmoShapeVerts = (
(0.0, 0.0, -0.47590911388397217), (-0.6069318056106567, 0.0, 0.7379544973373413),
(-1.0, 0.0, 1.0), (0.0, 0.0, -0.47590911388397217), (-1.0, 0.0, 1.0),
(0.0, 0.0, -1.0), (0.0, 0.0, -1.0), (1.0, 0.0, 1.0),
(0.6069318056106567, 0.0, 0.7379544973373413), (0.0, 0.0, -1.0),
(0.6069318056106567, 0.0, 0.7379544973373413), (0.0, 0.0, -0.47590911388397217),
(0.0, 0.0, -0.47590911388397217), (0.0, 0.0, 0.7379544973373413),
(-0.6069318056106567, 0.0, 0.7379544973373413), (0.0, 0.0, 1.0), (-1.0, 0.0, 1.0),
(-0.6069318056106567, 0.0, 0.7379544973373413), (0.0, 0.0, 1.0),
(-0.6069318056106567, 0.0, 0.7379544973373413), (0.0, 0.0, 0.7379544973373413),
(1.0, 0.0, 1.0), (0.0, 0.0, 1.0), (0.0, 0.0, 0.7379544973373413),
(1.0, 0.0, 1.0), (0.0, 0.0, 0.7379544973373413),
(0.6069318056106567, 0.0, 0.7379544973373413), (0.0, -1.0, 0.9999999403953552),
(0.0, 0.0, 0.9999999403953552), (0.0, 0.0, 0.7379544377326965),
(0.0, -1.0, 0.9999999403953552), (0.0, 0.0, 0.7379544377326965),
(0.0, -0.6069318056106567, 0.7379544377326965), (0.0, 0.0, -0.9999999403953552),
(0.0, -1.0, 0.9999999403953552), (0.0, -0.6069318056106567, 0.7379544377326965),
(0.0, 0.0, -0.9999999403953552), (0.0, -0.6069318056106567, 0.7379544377326965),
(0.0, 0.0, -0.4759090840816498))


class StarfieldSnapGizmo(Gizmo):
    bl_idname = "VIEW3D_starfield_snap_gizmo"
    bl_target_properties = ()
    __slots__ = (
        "custom_shape",
    )

    def draw(self, context):
        self.draw_custom_shape(self.custom_shape)

    def draw_select(self, context, select_id):
        self.draw_custom_shape(self.custom_shape, select_id=select_id)

    def setup(self):
        if not hasattr(self, "custom_shape"):
            self.custom_shape = self.new_custom_shape('TRIS', SnapGizmoShapeVerts)


class StarfieldSnapGizmoGroup(GizmoGroup):
    bl_idname = "OBJECT_starfield_snap_gizmo_group"
    bl_label = "Starfield Snap"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'WINDOW'
    bl_options = {'3D', 'PERSISTENT'}

    @classmethod
    def poll(cls, context):
        ob = context.object
        try:
            has_node_prop = ob.starfield_json is not None and ob.starfield_json.node_id
        except Exception:
            has_node_prop = False
        return (
            ob
            and ob.type == 'EMPTY'
            and has_node_prop
        )

    def setup(self, context):
        ob = context.object
        gz = self.gizmos.new(StarfieldSnapGizmo.bl_idname)
        gz.color = 1.0, 0.5, 1.0
        gz.alpha = 0.5
        gz.color_highlight = 1.0, 1.0, 1.0
        gz.alpha_highlight = 0.5
        # units are large, so shrink to something more reasonable.
        gz.scale_basis = 0.5
        gz.use_draw_modal = True
        self.starfield_snap_gizmo = gz

    def refresh(self, context):
        ob = context.object
        gz = self.starfield_snap_gizmo
        gz.matrix_basis = ob.matrix_world.normalized()


def menu_func_import(self, context):
    self.layout.operator(
        StarfieldJsonImport.bl_idname,
        text="Starfield JSON Import (.json)")


def menu_func_export(self, context):
    self.layout.operator(
        StarfieldJsonExport.bl_idname,
        text="Starfield JSON Export (.json)")


def register():
    bpy.utils.register_class(StarfieldJsonPropertyGroup)
    bpy.types.Object.starfield_json = PointerProperty(type=StarfieldJsonPropertyGroup)
    bpy.utils.register_class(StarfieldJsonPropertyGroupPanel)
    bpy.utils.register_class(StarfieldSnapGizmo)
    bpy.utils.register_class(StarfieldSnapGizmoGroup)
    bpy.utils.register_class(StarfieldJsonImport)
    bpy.utils.register_class(StarfieldJsonExport)
    bpy.types.TOPBAR_MT_file_import.append(menu_func_import)
    bpy.types.TOPBAR_MT_file_export.append(menu_func_export)


def unregister():
    bpy.utils.uregister_class(StarfieldJsonPropertyGroup)
    del bpy.types.Object.starfield_json
    bpy.utils.uregister_class(StarfieldJsonPropertyGroupPanel)
    bpy.utils.unregister_class(StarfieldSnapGizmo)
    bpy.utils.unregister_class(StarfieldSnapGizmoGroup)
    bpy.utils.unregister_class(StarfieldJsonImport)
    bpy.utils.unregister_class(StarfieldJsonExport)
    bpy.types.TOPBAR_MT_file_import.remove(menu_func_import)
    bpy.types.TOPBAR_MT_file_export.remove(menu_func_export)


if __name__ == "__main__":
    try:
        register()
    except Exception:
        pass

    #bpy.ops.starfield_cell_group_json.import_file('INVOKE_DEFAULT')
    #bpy.ops.starfield_cell_group_json.export_file('INVOKE_DEFAULT')
