using System.Collections.Generic;
using AccelDraw.Core.Interfaces;
using Autodesk.AutoCAD.DatabaseServices;
using Vec = AccelDraw.Geometry;

namespace AccelDraw.Plugin.AutoCAD
{
    /// <summary>
    /// Reads selected AutoCAD entities into normalized <see cref="Vec.VectorEntity"/> records
    /// (spec sections 8-9). This milestone supports LINE, LWPOLYLINE, CIRCLE, ARC, TEXT, MTEXT and
    /// BLOCKREFERENCE; anything else is recorded with EntityType.Unsupported instead of crashing.
    /// </summary>
    public class EntityReader : IVectorExtractor
    {
        public Vec.VectorDocument Extract(Database database, IEnumerable<ObjectId> objectIds)
        {
            var document = new Vec.VectorDocument();

            using (var tr = database.TransactionManager.StartTransaction())
            {
                int index = 0;
                foreach (var id in objectIds)
                {
                    index++;
                    var entity = (Entity)tr.GetObject(id, OpenMode.ForRead);
                    var vectorEntity = ReadEntity(tr, entity, index);
                    document.Entities.Add(vectorEntity);
                }

                tr.Commit();
            }

            return document;
        }

        private Vec.VectorEntity ReadEntity(Transaction tr, Entity entity, int index)
        {
            var result = new Vec.VectorEntity
            {
                Id = $"entity-{index:D5}",
                SourceHandle = entity.Handle.ToString(),
                SourceObjectType = entity.GetRXClass().Name,
                Properties = ReadProperties(entity)
            };

            switch (entity)
            {
                case Line line:
                    result.EntityType = Vec.EntityType.Line;
                    result.Geometry = new Vec.EntityGeometry
                    {
                        Start = ToPoint3D(line.StartPoint),
                        End = ToPoint3D(line.EndPoint)
                    };
                    result.Transform = new Vec.Transform();
                    break;

                case Polyline poly:
                    result.EntityType = Vec.EntityType.LwPolyline;
                    result.Geometry = ReadPolyline(poly);
                    result.Transform = new Vec.Transform { Normal = ToPoint3D(poly.Normal) };
                    break;

                case Circle circle:
                    result.EntityType = Vec.EntityType.Circle;
                    result.Geometry = new Vec.EntityGeometry
                    {
                        Center = ToPoint3D(circle.Center),
                        Radius = circle.Radius,
                        Normal = ToPoint3D(circle.Normal)
                    };
                    result.Transform = new Vec.Transform { Normal = ToPoint3D(circle.Normal) };
                    break;

                case Arc arc:
                    result.EntityType = Vec.EntityType.Arc;
                    result.Geometry = new Vec.EntityGeometry
                    {
                        Center = ToPoint3D(arc.Center),
                        Radius = arc.Radius,
                        StartAngle = arc.StartAngle,
                        EndAngle = arc.EndAngle,
                        Normal = ToPoint3D(arc.Normal)
                    };
                    result.Transform = new Vec.Transform { Normal = ToPoint3D(arc.Normal) };
                    break;

                case MText mtext:
                    result.EntityType = Vec.EntityType.MText;
                    result.Geometry = new Vec.EntityGeometry
                    {
                        Position = ToPoint3D(mtext.Location),
                        Height = mtext.TextHeight,
                        Rotation = mtext.Rotation,
                        TextValue = mtext.Contents
                    };
                    result.Transform = new Vec.Transform { Rotation = mtext.Rotation };
                    break;

                case DBText text:
                    result.EntityType = Vec.EntityType.Text;
                    result.Geometry = new Vec.EntityGeometry
                    {
                        Position = ToPoint3D(text.Position),
                        Height = text.Height,
                        Rotation = text.Rotation,
                        TextValue = text.TextString
                    };
                    result.Transform = new Vec.Transform { Rotation = text.Rotation };
                    break;

                case BlockReference blockRef:
                    result.EntityType = Vec.EntityType.BlockReference;
                    var btr = (BlockTableRecord)tr.GetObject(blockRef.BlockTableRecord, OpenMode.ForRead);
                    result.Geometry = new Vec.EntityGeometry
                    {
                        BlockName = btr.Name,
                        InsertionPoint = ToPoint3D(blockRef.Position),
                        Rotation = blockRef.Rotation,
                        Scale = new Vec.Point3D(blockRef.ScaleFactors.X, blockRef.ScaleFactors.Y, blockRef.ScaleFactors.Z)
                    };
                    result.Transform = new Vec.Transform
                    {
                        Rotation = blockRef.Rotation,
                        Scale = new Vec.Point3D(blockRef.ScaleFactors.X, blockRef.ScaleFactors.Y, blockRef.ScaleFactors.Z)
                    };
                    break;

                default:
                    result.EntityType = Vec.EntityType.Unsupported;
                    break;
            }

            return result;
        }

        private static Vec.EntityGeometry ReadPolyline(Polyline poly)
        {
            var vertices = new List<Vec.Point3D>();
            var bulges = new List<double>();

            for (int i = 0; i < poly.NumberOfVertices; i++)
            {
                vertices.Add(ToPoint3D(poly.GetPoint3dAt(i)));
                bulges.Add(poly.GetBulgeAt(i));
            }

            return new Vec.EntityGeometry
            {
                Vertices = vertices,
                Bulges = bulges,
                IsClosed = poly.Closed
            };
        }

        private static Vec.EntityProperties ReadProperties(Entity entity)
        {
            return new Vec.EntityProperties
            {
                Layer = entity.Layer,
                Color = entity.ColorIndex,
                Linetype = entity.Linetype,
                Lineweight = (int)entity.LineWeight
            };
        }

        private static Vec.Point3D ToPoint3D(Autodesk.AutoCAD.Geometry.Point3d p) => new Vec.Point3D(p.X, p.Y, p.Z);

        private static Vec.Point3D ToPoint3D(Autodesk.AutoCAD.Geometry.Vector3d v) => new Vec.Point3D(v.X, v.Y, v.Z);
    }
}
