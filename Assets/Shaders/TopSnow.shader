Shader "Custom/TopSnow"
{
    Properties
    {
        _MainTex("Albedo (RGB)", 2D) = "white" {}
        _Color("Color", Color) = (1,1,1,1)

        [HDR]_SnowColor("Snow Color", Color) = (1,1,1,1)
        _SnowAmount("Snow Amount", Range(0,1)) = 1

        _TopStart("Top Start (0=Bottom, 1=Top)", Range(0,1)) = 0.6
        _TopSoftness("Top Softness", Range(0.001,0.5)) = 0.12

        _SlopeInfluence("Slope Influence", Range(0,1)) = 0.6
        _SlopePower("Slope Power", Range(0.1,8)) = 2

        _NoiseScale("Noise Scale", Float) = 4
        _NoiseInfluence("Noise Influence", Range(0,1)) = 0.2

        _BaseSmoothness("Base Smoothness", Range(0,1)) = 0.4
        _SnowSmoothness("Snow Smoothness", Range(0,1)) = 0.75
        _Metallic("Metallic", Range(0,1)) = 0

        [HideInInspector]_MinWorldY("Min World Y", Float) = 0
        [HideInInspector]_MaxWorldY("Max World Y", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }
        LOD 300

        CGPROGRAM
        #pragma target 3.0
        #pragma surface surf Standard fullforwardshadows addshadow

        sampler2D _MainTex;
        float4 _Color;
        float4 _SnowColor;

        float _SnowAmount;
        float _TopStart;
        float _TopSoftness;
        float _SlopeInfluence;
        float _SlopePower;
        float _NoiseScale;
        float _NoiseInfluence;

        float _BaseSmoothness;
        float _SnowSmoothness;
        float _Metallic;
        float _MinWorldY;
        float _MaxWorldY;

        struct Input
        {
            float2 uv_MainTex;
            float3 worldPos;
            float3 worldNormal;
        };

        float Hash21(float2 p)
        {
            p = frac(p * float2(123.34, 456.21));
            p += dot(p, p + 34.345);
            return frac(p.x * p.y);
        }

        float ValueNoise(float2 p)
        {
            float2 i = floor(p);
            float2 f = frac(p);
            float2 u = f * f * (3.0 - 2.0 * f);

            float a = Hash21(i + float2(0.0, 0.0));
            float b = Hash21(i + float2(1.0, 0.0));
            float c = Hash21(i + float2(0.0, 1.0));
            float d = Hash21(i + float2(1.0, 1.0));

            float x1 = lerp(a, b, u.x);
            float x2 = lerp(c, d, u.x);
            return lerp(x1, x2, u.y);
        }

        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            float3 worldNormal = normalize(IN.worldNormal);
            float3 baseAlbedo = tex2D(_MainTex, IN.uv_MainTex).rgb * _Color.rgb;

            float minY = _MinWorldY;
            float maxY = _MaxWorldY;
            float heightRange = maxY - minY;

            // If bounds were not provided yet, approximate with object pivot/scale.
            if (heightRange < 1e-4)
            {
                float pivotY = unity_ObjectToWorld._m13;
                float3 localUpWS = float3(unity_ObjectToWorld._m01, unity_ObjectToWorld._m11, unity_ObjectToWorld._m21);
                float approxHalfHeight = max(0.25, length(localUpWS));
                minY = pivotY - approxHalfHeight;
                maxY = pivotY + approxHalfHeight;
                heightRange = maxY - minY;
            }

            float height01 = saturate((IN.worldPos.y - minY) / max(1e-4, heightRange));
            float topMask = smoothstep(_TopStart - _TopSoftness, _TopStart + _TopSoftness, height01);

            float upMask = pow(saturate(dot(worldNormal, float3(0, 1, 0))), max(0.001, _SlopePower));
            float slopeMask = lerp(1.0, upMask, _SlopeInfluence);

            float noise = ValueNoise(IN.worldPos.xz * _NoiseScale);
            float noiseMask = lerp(1.0, noise, _NoiseInfluence);

            float snowMask = saturate(topMask * slopeMask * noiseMask * _SnowAmount);

            float3 snowTarget = max(baseAlbedo, _SnowColor.rgb);
            o.Albedo = lerp(baseAlbedo, snowTarget, snowMask);
            o.Metallic = _Metallic;
            o.Smoothness = lerp(_BaseSmoothness, _SnowSmoothness, snowMask);
            o.Alpha = 1;
        }
        ENDCG
    }

    FallBack "Diffuse"
}
