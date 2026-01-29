using UnityEngine;
    
    public class PlayerSnowInteraction : MonoBehaviour
    {
        [SerializeField] private float deformRadius = 0.5f;
        [SerializeField] private float deformStrength = 0.05f;
        
        private SnowDeformation snowDeformation;
    
        private void Start()
        {
            snowDeformation = FindObjectOfType<SnowDeformation>();
        }
    
        private void Update()
        {
            if (!Physics.Raycast(transform.position, Vector3.down, out var hit, 1f)) return;
            if (hit.collider.GetComponent<SnowDeformation>())
            {
                snowDeformation.DeformAtPosition(hit.point, deformRadius, deformStrength);
            }
        }
    }