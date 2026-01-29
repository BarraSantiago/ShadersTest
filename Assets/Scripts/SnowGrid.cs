using UnityEngine;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class SnowGrid : MonoBehaviour
{
    [SerializeField] private int gridSize = 100;
    [SerializeField] private float cellSize = 0.1f;

    private void Start()
    {
        GenerateMesh();
    }

    private void GenerateMesh()
    {
        Mesh mesh = new Mesh();
        MeshFilter meshFilter = GetComponent<MeshFilter>();
        meshFilter.mesh = mesh;

        Vector3[] vertices = new Vector3[(gridSize + 1) * (gridSize + 1)];
        Vector2[] uv = new Vector2[vertices.Length];
        int[] triangles = new int[gridSize * gridSize * 6];

        for (int i = 0, y = 0; y <= gridSize; y++)
        {
            for (int x = 0; x <= gridSize; x++, i++)
            {
                vertices[i] = new Vector3(x * cellSize, 0, y * cellSize);
                uv[i] = new Vector2((float)x / gridSize, (float)y / gridSize);
            }
        }

        for (int ti = 0, vi = 0, y = 0; y < gridSize; y++, vi++)
        {
            for (int x = 0; x < gridSize; x++, ti += 6, vi++)
            {
                triangles[ti] = vi;
                triangles[ti + 3] = triangles[ti + 2] = vi + 1;
                triangles[ti + 4] = triangles[ti + 1] = vi + gridSize + 1;
                triangles[ti + 5] = vi + gridSize + 2;
            }
        }

        mesh.vertices = vertices;
        mesh.uv = uv;
        mesh.triangles = triangles;
        mesh.RecalculateNormals();
        
        if (meshFilter != null && meshFilter.mesh != null)
        {
            Debug.Log(
                $"Vertices: {meshFilter.mesh.vertexCount}, UVs: {meshFilter.mesh.uv.Length}, Normals: {meshFilter.mesh.normals.Length}");
        }
    }
}