using UnityEngine;

public class SnowDeformation : MonoBehaviour
{
    [SerializeField] private Material snowMaterial;
    [SerializeField] private int heightMapResolution = 512;
    [SerializeField] private float deformationStrength = 0.1f;
    [SerializeField] private float deformationRadius = 1f;
    [SerializeField] private LayerMask deformableLayer;
    [SerializeField] private GameObject snowLayerPrefab; // Assign in inspector

    private GameObject snowLayerInstance;
    private RenderTexture heightMap;
    private RenderTexture tempHeightMap;
    private Material deformationMaterial;

    private void Start()
    {
        MeshFilter meshFilter = GetComponent<MeshFilter>();
        if (meshFilter != null && meshFilter.mesh != null)
        {
            Debug.Log(
                $"Vertices: {meshFilter.mesh.vertexCount}, UVs: {meshFilter.mesh.uv.Length}, Normals: {meshFilter.mesh.normals.Length}");
        }

        Shader snowShader = Shader.Find("Custom/DeformableSnow");
        if (snowShader == null)
        {
            Debug.LogError("DeformableSnow shader not found!");
        }

        CreateSnowLayer();

        InitializeHeightMap();
        CreateDeformationMaterial();
    }

    private void Update()
    {
        if (Input.GetKeyDown(KeyCode.Space))
        {
            Debug.Log($"HeightMap: {heightMap}, Material: {snowMaterial}");
        }

        // Add mouse click deformation
        if (Input.GetMouseButton(0)) // Left mouse button
        {
            Ray ray = Camera.main.ScreenPointToRay(Input.mousePosition);
            if (Physics.Raycast(ray, out RaycastHit hit, 100f, deformableLayer))
            {
                DeformAtPosition(hit.point, deformationRadius, deformationStrength);
            }
        }

        // Or test with a key press at object center
        if (Input.GetKeyDown(KeyCode.D))
        {
            Vector3 testPos = transform.position;
            DeformAtPosition(testPos, deformationRadius, deformationStrength);
            Debug.Log("Manual deformation triggered!");
        }
    }

    private void InitializeHeightMap()
    {
        heightMap = new RenderTexture(heightMapResolution, heightMapResolution, 0, RenderTextureFormat.RFloat);
        heightMap.filterMode = FilterMode.Bilinear;
        heightMap.wrapMode = TextureWrapMode.Clamp;

        tempHeightMap = new RenderTexture(heightMapResolution, heightMapResolution, 0, RenderTextureFormat.RFloat);
        tempHeightMap.filterMode = FilterMode.Bilinear;

        RenderTexture.active = heightMap;
        GL.Clear(true, true, Color.white); // Start with full snow
        RenderTexture.active = null;

        snowMaterial.SetTexture("_HeightMap", heightMap);
        snowMaterial.SetFloat("_Displacement", 1.0f); // Increase this value to see more snow
    }

    private void CreateDeformationMaterial()
    {
        Shader deformShader = Shader.Find("Hidden/SnowDeform");
        if (deformShader == null)
        {
            Debug.LogError("SnowDeform shader not found!");
            return;
        }

        deformationMaterial = new Material(deformShader);
    }

    private void CreateSnowLayer()
    {
        // Copy the mesh
        MeshFilter baseMeshFilter = GetComponent<MeshFilter>();

        snowLayerInstance = new GameObject("SnowLayer");
        snowLayerInstance.transform.SetParent(transform);
        snowLayerInstance.transform.localPosition = Vector3.zero;
        snowLayerInstance.transform.localRotation = Quaternion.identity;
        snowLayerInstance.transform.localScale = Vector3.one;

        MeshFilter snowMeshFilter = snowLayerInstance.AddComponent<MeshFilter>();
        snowMeshFilter.mesh = baseMeshFilter.mesh;

        MeshRenderer snowRenderer = snowLayerInstance.AddComponent<MeshRenderer>();
        snowRenderer.material = snowMaterial; // This uses the DeformableSnow shader
    }

    public void DeformAtPosition(Vector3 worldPos, float radius, float strength)
    {
        Vector3 localPos = transform.InverseTransformPoint(worldPos);
        Vector2 uv = new Vector2(
            (localPos.x / transform.localScale.x) + 0.5f,
            (localPos.z / transform.localScale.z) + 0.5f
        );

        deformationMaterial.SetVector("_DeformPos", uv);
        deformationMaterial.SetFloat("_DeformRadius", radius / transform.localScale.x);
        deformationMaterial.SetFloat("_DeformStrength", strength);

        Graphics.Blit(heightMap, tempHeightMap, deformationMaterial);
        Graphics.Blit(tempHeightMap, heightMap);
    }

    private void OnGUI()
    {
        if (heightMap != null)
        {
            GUI.DrawTexture(new Rect(10, 10, 256, 256), heightMap);
        }
    }

    private void OnDestroy()
    {
        if (heightMap) heightMap.Release();
        if (tempHeightMap) tempHeightMap.Release();
    }
}