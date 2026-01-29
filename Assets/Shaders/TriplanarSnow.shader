Shader "URP/TriplanarSnow"
{
    Properties
    {
        // Base (under snow)
        _BaseAlbedo("Base Albedo", 2D) = "white" {}
        _BaseNormal("Base Normal", 2D) = "bump" {}
        _BaseNormalStrength("Base Normal Strength", Range(0,2)) = 1

        // Snow layer
        _SnowAlbedo("Snow Albedo", 2D) = "white" {}
        _SnowNormal("Snow Normal", 2D) = "bump" {}
        _SnowNormalStrength("Snow Normal Strength", Range(0,2)) = 1
        _SnowTint("Snow Tint", Color) = (1,1,1,1)

        // Triplanar controls
        _TilingXYZ("World Tiling (X,Y,Z)", Vector) = (0.5,0.5,0.5,0)
        _OffsetXYZ("World Offset (X,Y,Z)", Vector) = (0,0,0,0)
        _BlendSharpness("Triplanar Blend Sharpness", Range(0.1, 8)) = 3

        // Snow placement
        _HeightStart("Height Start (world Y)", Float) = 0
        _HeightEnd("Height End (world Y)", Float) = 10
        _SlopeStartDeg("Slope Start (deg, flatter gets snow)", Range(0,90)) = 25
        _SlopeEndDeg("Slope End (deg)", Range(0,90)) = 65
        _SnowIntensity("Snow Intensity (global)", Range(0,2)) = 1

        // Optional external mask (R adds snow, G removes)
        _SnowMask("Snow Mask (RG)", 2D) = "black" {}
        _SnowMask_ST("SnowMask ST", Vector) = (1,1,0,0)
        _SnowMaskInfluence("Snow Mask Influence", Range(0,2)) = 1

        // PBR
        _Metallic("Metallic", Range(0,1)) = 0
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Occlusion("Occlusion", Range(0,1)) = 1

        // LOD
        [Toggle(_TRI_RNM_ON)] _RNM("Use RNM Normal Blending", Float) = 1
    }

    SubShader
    {
        Tags{
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags{"LightMode"="UniversalForward"}
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP lighting variants
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION

            // Local feature toggles
            #pragma multi_compile_local_fragment _ _TRI_RNM_ON

            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Textures & samplers
            TEXTURE2D(_BaseAlbedo);  SAMPLER(sampler_BaseAlbedo);
            TEXTURE2D(_BaseNormal);  SAMPLER(sampler_BaseNormal);
            TEXTURE2D(_SnowAlbedo);  SAMPLER(sampler_SnowAlbedo);
            TEXTURE2D(_SnowNormal);  SAMPLER(sampler_SnowNormal);
            TEXTURE2D(_SnowMask);    SAMPLER(sampler_SnowMask);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseAlbedo_ST;
                float  _BaseNormalStrength;

                float4 _SnowAlbedo_ST;
                float  _SnowNormalStrength;
                float4 _SnowTint;

                float4 _TilingXYZ;
                float4 _OffsetXYZ;
                float  _BlendSharpness;

                float  _HeightStart;
                float  _HeightEnd;
                float  _SlopeStartDeg;
                float  _SlopeEndDeg;
                float  _SnowIntensity;

                float4 _SnowMask_ST;
                float  _SnowMaskInfluence;

                float  _Metallic;
                float  _Smoothness;
                float  _Occlusion;
            CBUFFER_END

            struct Attributes {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 uv0          : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings {
                float4 positionCS   : SV_POSITION;
                float3 positionWS   : TEXCOORD0;
                float3 normalWS     : TEXCOORD1;
                float3 viewDirWS    : TEXCOORD2;
                float4 shadowCoord  : TEXCOORD3;
                float  fogFactor    : TEXCOORD4;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            inline float2 ProjectUV(float3 pWS, int axis)
            {
                // axis: 0=X, 1=Y, 2=Z
                if (axis == 0) return pWS.zy * _TilingXYZ.yz + _OffsetXYZ.yz;
                if (axis == 1) return pWS.xz * _TilingXYZ.xz + _OffsetXYZ.xz;
                return pWS.xy * _TilingXYZ.xy + _OffsetXYZ.xy;
            }

            inline void GetAxisBasis(int axis, out float3 T, out float3 B, out float3 N)
            {
                if (axis == 0) { N=float3(1,0,0); T=float3(0,0,1); B=float3(0,1,0); }
                else if(axis==1){ N=float3(0,1,0); T=float3(1,0,0); B=float3(0,0,1); }
                else            { N=float3(0,0,1); T=float3(1,0,0); B=float3(0,1,0); }
            }

            inline float3 TangentToWorld(float3 nTS, int axis)
            {
                float3 T,B,N; GetAxisBasis(axis, T,B,N);
                return normalize(nTS.x*T + nTS.y*B + nTS.z*N);
            }

            inline float3 RNM(float3 n, float3 b)
            {
                // Re-oriented normal mapping (both in [-1,1])
                float3 t = float3(n.xy + b.xy, n.z*b.z);
                float3 r = float3(t.xy, n.z*b.z - dot(n.xy, b.xy));
                return normalize(r);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 nWS   = TransformObjectToWorldNormal(v.normalOS);

                o.positionWS  = posWS;
                o.normalWS    = normalize(nWS);
                o.viewDirWS   = GetWorldSpaceViewDir(posWS);
                o.positionCS  = TransformWorldToHClip(posWS);
                o.shadowCoord = TransformWorldToShadowCoord(posWS);
                o.fogFactor   = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            struct SurfOut {
                float3 albedo;
                float3 normalWS;
            };

            SurfOut TriplanarSampleBase(float3 posWS, float3 nWS)
            {
                SurfOut o;
                float3 nAbs = abs(nWS);
                float3 w = pow(nAbs, _BlendSharpness);
                w /= (w.x + w.y + w.z + 1e-5);

                float3 albedo = 0;
                float3 nBlend = 0;

                [unroll] for (int axis=0; axis<3; ++axis)
                {
                    float2 uv = ProjectUV(posWS, axis);
                    float3 a  = SAMPLE_TEXTURE2D(_BaseAlbedo, sampler_BaseAlbedo, uv).rgb;
                    float3 nT = SAMPLE_TEXTURE2D(_BaseNormal, sampler_BaseNormal, uv).xyz * 2.0 - 1.0;
                    nT.xy *= _BaseNormalStrength; nT = normalize(nT);

                    #if defined(_TRI_RNM_ON)
                        float3 nR = RNM(nT, float3(0,0,1));
                        float3 nW = TangentToWorld(nR, axis);
                    #else
                        float3 nW = TangentToWorld(nT, axis);
                    #endif

                    albedo += a * w[axis];
                    nBlend += nW * w[axis];
                }

                o.albedo   = albedo;
                o.normalWS = normalize(nBlend);
                return o;
            }

            SurfOut TriplanarSampleSnow(float3 posWS, float3 nWS)
            {
                SurfOut o;
                float3 nAbs = abs(nWS);
                float3 w = pow(nAbs, _BlendSharpness);
                w /= (w.x + w.y + w.z + 1e-5);

                float3 albedo = 0;
                float3 nBlend = 0;

                [unroll] for (int axis=0; axis<3; ++axis)
                {
                    float2 uv = ProjectUV(posWS, axis);
                    float3 a  = SAMPLE_TEXTURE2D(_SnowAlbedo, sampler_SnowAlbedo, uv).rgb;
                    float3 nT = SAMPLE_TEXTURE2D(_SnowNormal, sampler_SnowNormal, uv).xyz * 2.0 - 1.0;
                    nT.xy *= _SnowNormalStrength; nT = normalize(nT);

                    #if defined(_TRI_RNM_ON)
                        float3 nR = RNM(nT, float3(0,0,1));
                        float3 nW = TangentToWorld(nR, axis);
                    #else
                        float3 nW = TangentToWorld(nT, axis);
                    #endif

                    albedo += a * w[axis];
                    nBlend += nW * w[axis];
                }

                o.albedo   = albedo * _SnowTint.rgb;
                o.normalWS = normalize(nBlend);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 nWS = normalize(i.normalWS);

                // Base & Snow triplanar
                SurfOut baseM = TriplanarSampleBase(i.positionWS, nWS);
                SurfOut snowM = TriplanarSampleSnow(i.positionWS, nWS);

                // Height mask
                float h = saturate( (i.positionWS.y - _HeightStart) / max(1e-5, (_HeightEnd - _HeightStart)) );

                // Slope mask (convert degrees to cos thresholds)
                float cosStart = cos(radians(_SlopeStartDeg));
                float cosEnd   = cos(radians(_SlopeEndDeg));
                float c = saturate(dot(nWS, float3(0,1,0))); // 1 flat up, 0 vertical
                float sMask = saturate( (c - cosEnd) / max(1e-5, (cosStart - cosEnd)) );

                float snowAmount = saturate(max(h, sMask) * _SnowIntensity);

                // External mask (R adds, G removes)
                float2 maskUV = i.positionWS.xz * _SnowMask_ST.xy + _SnowMask_ST.zw;
                float2 rg = SAMPLE_TEXTURE2D(_SnowMask, sampler_SnowMask, maskUV).rg;
                snowAmount = saturate( snowAmount + (rg.r - rg.g) * _SnowMaskInfluence );

                // Blend base<->snow
                float3 albedo   = lerp(baseM.albedo, snowM.albedo, snowAmount);
                float3 normalWS = normalize(lerp(baseM.normalWS, snowM.normalWS, snowAmount));

                // Build URP structs
                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;
                inputData.normalWS = normalWS;
                inputData.viewDirectionWS = normalize(i.viewDirWS);
                inputData.shadowCoord = i.shadowCoord;
                inputData.fogCoord = i.fogFactor;
                //inputData.renderingLayers = GetMeshRenderingLayer();

                SurfaceData surface = (SurfaceData)0;
                surface.albedo     = albedo;
                surface.metallic   = _Metallic;
                surface.smoothness = _Smoothness;
                surface.occlusion  = _Occlusion;
                surface.normalTS   = float3(0,0,1); // using WS normal above
                surface.emission   = 0;
                surface.alpha      = 1;

                half4 col = UniversalFragmentPBR(inputData, surface);
                col.rgb = MixFog(col.rgb, i.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
