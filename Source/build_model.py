import bpy, math, json, os
from mathutils import Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
materials={}
def mat(name,color,metal=0,rough=.3):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough; materials[name]=m; return m
white=mat('Porcelain',(0.91,.915,.90),.05,.24)
chrome=mat('Polished steel',(.57,.61,.65),.95,.19)
wheel=mat('Click wheel',(.77,.79,.79),.08,.48)
center=mat('Select button',(.9,.91,.9),.12,.3)
black=mat('Recess',(.055,.065,.075),.3,.2)
lcd=mat('LCD surround',(.23,.27,.28),.2,.32)
def box(name,loc,scale,material,bevel):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc); o=bpy.context.object; o.name=name; o.dimensions=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 o.data.materials.append(material)
 if bevel:
  b=o.modifiers.new('Machined radii','BEVEL'); b.width=bevel; b.segments=8
  bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=b.name)
 for p in o.data.polygons:p.use_smooth=True
 n=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL'); n.keep_sharp=True; bpy.ops.object.modifier_apply(modifier=n.name)
 return o
def cyl(name,loc,radius,depth,material):
 bpy.ops.mesh.primitive_cylinder_add(vertices=128,radius=radius,depth=depth,location=loc); o=bpy.context.object; o.name=name; o.data.materials.append(material)
 b=o.modifiers.new('Soft edge','BEVEL'); b.width=.045; b.segments=4; bpy.ops.object.modifier_apply(modifier=b.name)
 for p in o.data.polygons:p.use_smooth=True
 return o
box('Chrome back',(0,0,-.14),(6.2,10.4,.86),chrome,.40)
box('White front',(0,0,.23),(6.18,10.38,.60),white,.37)
box('Screen gasket',(0,2.12,.54),(4.99,3.85,.075),black,.16)
box('Screen frame',(0,2.12,.587),(4.82,3.68,.042),lcd,.11)
cyl('Wheel recess',(0,-2.36,.535),2.12,.06,black)
cyl('Click wheel',(0,-2.36,.575),2.08,.055,wheel)
cyl('Center seam',(0,-2.36,.61),.77,.035,lcd)
cyl('Select button',(0,-2.36,.64),.735,.075,center)
box('Hold slot',(-1.6,5.19,-.08),(.85,.07,.31),black,.035)
box('Hold switch',(-1.77,5.235,-.08),(.38,.08,.25),white,.03)
# Connector inset in the underside.
box('Dock connector',(0,-5.192,-.08),(1.9,.045,.30),black,.065)
# Headphone socket on upper edge.
bpy.ops.mesh.primitive_cylinder_add(vertices=48,radius=.16,depth=.04,location=(1.65,5.2,-.1),rotation=(math.pi/2,0,0)); bpy.context.object.name='Headphone socket'; bpy.context.object.data.materials.append(black)
# Export actual evaluated Blender mesh geometry for SceneKit, preserving normals.
result=[]
deps=bpy.context.evaluated_depsgraph_get()
for o in bpy.context.scene.objects:
 if o.type!='MESH':continue
 eo=o.evaluated_get(deps); mesh=eo.to_mesh(); mesh.calc_loop_triangles()
 verts=[]; normals=[]; indices=[]
 normal_matrix=o.matrix_world.to_3x3().inverted().transposed()
 for tri in mesh.loop_triangles:
  for li in tri.loops:
   loop=mesh.loops[li]; v=o.matrix_world @ mesh.vertices[loop.vertex_index].co; n=(normal_matrix @ mesh.corner_normals[li].vector).normalized()
   indices.append(len(indices)); verts.extend(v); normals.extend(n)
 m=o.data.materials[0]; bs=m.node_tree.nodes.get('Principled BSDF')
 result.append(dict(name=o.name,vertices=verts,normals=normals,indices=indices,color=list(m.diffuse_color),metalness=bs.inputs['Metallic'].default_value,roughness=bs.inputs['Roughness'].default_value))
 eo.to_mesh_clear()
os.makedirs(ROOT+'/Assets',exist_ok=True)
with open(ROOT+'/Assets/ipod-mesh.json','w') as f:json.dump(result,f,separators=(',',':'))
# Save an editable, lit Blender scene as well.
bpy.ops.object.camera_add(location=(12,-15,18)); cam=bpy.context.object; cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler(); bpy.context.scene.camera=cam
for loc,power,size in [((0,7,12),1800,8),((-8,1,8),1300,7),((7,-4,3),900,5)]:
 bpy.ops.object.light_add(type='AREA',location=loc); l=bpy.context.object; l.data.energy=power;l.data.shape='DISK';l.data.size=size;l.rotation_euler=(-l.location).to_track_quat('-Z','Y').to_euler()
bpy.context.scene.world.color=(.2,.2,.2)
bpy.ops.wm.save_as_mainfile(filepath=ROOT+'/Assets/iPod.blend')
print('EXPORTED',len(result),'Blender meshes')
