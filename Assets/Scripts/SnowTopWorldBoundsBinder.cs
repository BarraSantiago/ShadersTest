using UnityEngine;

[ExecuteAlways]
[DisallowMultipleComponent]
public class SnowTopWorldBoundsBinder : MonoBehaviour
{
    [SerializeField] private Renderer _targetRenderer;
    [SerializeField] private float _padding = 0f;
    [SerializeField] private bool _updateEveryFrame = true;

    private static readonly int MinWorldY = Shader.PropertyToID("_MinWorldY");
    private static readonly int MaxWorldY = Shader.PropertyToID("_MaxWorldY");

    private MaterialPropertyBlock _propertyBlock;

    private void Reset()
    {
        _targetRenderer = GetComponent<Renderer>();
    }

    private void OnEnable()
    {
        EnsureReferences();
        ApplyBounds();
    }

    private void OnValidate()
    {
        EnsureReferences();
        ApplyBounds();
    }

    private void LateUpdate()
    {
        if (!_updateEveryFrame)
        {
            return;
        }

        ApplyBounds();
    }

    [ContextMenu("Update Snow Bounds Now")]
    private void UpdateSnowBoundsNow()
    {
        EnsureReferences();
        ApplyBounds();
    }

    private void EnsureReferences()
    {
        if (_targetRenderer == null)
        {
            _targetRenderer = GetComponent<Renderer>();
        }

        if (_propertyBlock == null)
        {
            _propertyBlock = new MaterialPropertyBlock();
        }
    }

    private void ApplyBounds()
    {
        if (_targetRenderer == null)
        {
            return;
        }

        Bounds bounds = _targetRenderer.bounds;
        float minY = bounds.min.y - _padding;
        float maxY = bounds.max.y + _padding;

        if (maxY - minY < 1e-4f)
        {
            maxY = minY + 1e-4f;
        }

        _targetRenderer.GetPropertyBlock(_propertyBlock);
        _propertyBlock.SetFloat(MinWorldY, minY);
        _propertyBlock.SetFloat(MaxWorldY, maxY);
        _targetRenderer.SetPropertyBlock(_propertyBlock);
    }
}
