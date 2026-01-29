Shader "Custom/InteractiveSnowURP"
{
    Properties
    {
        [HDR]_SnowColor("Snow Color", Color) = (1,1,1,1)

        _SnowScale("Snow Scale", Float) = 80
        _SnowPower("Snow Power", Float) = 2
        _SnowBrightness("Snow Brightness", Float) = 1

        _VertexOffset("Vertex Offset", Float) = 0.025

        _RenderTex("Render Texture", 2D) = "black" {}
        _Smoothness("Smoothness", Range(0,1)) = 0.25
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalRenderPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // URP lighting variants (keep some common ones)
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _LIGHTMAP_ON
            #pragma multi_compile _ _DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _SCREEN_SPACE_OCCLUSION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/SurfaceInput.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _SnowColor;
                float _SnowScale;
                float _SnowPower;
                float _SnowBrightness;
                float _VertexOffset;
                float _Smoothness;
                float4 _RenderTex_ST;
            CBUFFER_END

            TEXTURE2D(_RenderTex);
            SAMPLER(sampler_RenderTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD3;
                #endif

                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // --- tiny procedural noise (value noise) ---
            float hash21(float2 p)
            {
                // cheap-ish hash: stable, fast, good enough for snow fuzz
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);

                // smoothstep curve
                float2 u = f * f * (3.0 - 2.0 * f);

                float a = hash21(i + float2(0, 0));
                float b = hash21(i + float2(1, 0));
                float c = hash21(i + float2(0, 1));
                float d = hash21(i + float2(1, 1));

                float x1 = lerp(a, b, u.x);
                float x2 = lerp(c, d, u.x);
                return lerp(x1, x2, u.y);
            }

            float fbm(float2 p)
            {
                // 3 octaves for nicer “snowy” breakup
                float n = 0.0;
                float amp = 0.5;
                float freq = 1.0;

                [unroll]
                for (int o = 0; o < 3; o++)
                {
                    n += amp * valueNoise(p * freq);
                    freq *= 2.0;
                    amp *= 0.5;
                }
                return saturate(n);
            }

            float computeSnowMask(float2 uv)
            {
                float n = fbm(uv * _SnowScale);

                // like Shader Graph: Power then Brightness multiply
                n = pow(saturate(n), max(0.0001, _SnowPower));
                n *= _SnowBrightness;
                return n;
            }

            float computeInteraction(float2 uv)
            {
                // sample in vertex stage => must use LOD
                float2 ruv = TRANSFORM_TEX(uv, _RenderTex);
                float rt = SAMPLE_TEXTURE2D_LOD(_RenderTex, sampler_RenderTex, ruv, 0).r;

                // One Minus (white particles => depressions)
                return 1.0 - rt;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float2 uv = IN.uv;

                float snow = computeSnowMask(uv);
                float interact = computeInteraction(uv);

                // combine like the graph: noise + (1 - renderTex)
                float heightMask = snow + interact;

                float3 posOS = IN.positionOS.xyz;
                posOS.y += heightMask * _VertexOffset;

                VertexPositionInputs vp = GetVertexPositionInputs(posOS);
                VertexNormalInputs vn = GetVertexNormalInputs(IN.normalOS);

                OUT.positionCS = vp.positionCS;
                OUT.positionWS = vp.positionWS;
                OUT.normalWS = vn.normalWS;
                OUT.uv = uv;

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                OUT.shadowCoord = GetShadowCoord(vp);
                #endif

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                float snow = computeSnowMask(IN.uv);

                // Base color = snow * SnowColor
                half3 albedo = (half3)(_SnowColor.rgb * snow);

                SurfaceData surfaceData;
                    ZERO_INITIALIZE(SurfaceData, surfaceData);
                surfaceData.albedo = albedo;
                surfaceData.alpha = 1;
                surfaceData.metallic = 0;
                surfaceData.smoothness = _Smoothness;
                surfaceData.normalTS = half3(0, 0, 1);
                surfaceData.occlusion = 1;
                surfaceData.emission = 0;

                InputData inputData;
                    ZERO_INITIALIZE(InputData, inputData);
                inputData.positionWS = IN.positionWS;
                inputData.normalWS = normalize(IN.normalWS);
                inputData.viewDirectionWS = normalize(GetWorldSpaceViewDir(IN.positionWS));

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                inputData.shadowCoord = IN.shadowCoord;
                #else
                inputData.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                #endif

                inputData.fogCoord = ComputeFogFactor(IN.positionCS.z);
                inputData.vertexLighting = VertexLighting(IN.positionWS, inputData.normalWS);
                inputData.bakedGI = SAMPLE_GI(IN.uv, IN.positionWS, inputData.normalWS);

                half4 col = UniversalFragmentPBR(inputData, surfaceData);
                col.rgb = MixFog(col.rgb, inputData.fogCoord);
                return col;
            }
            ENDHLSL
        }

        // Shadow pass with SAME displacement (so shadows match).
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode"="ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _SnowColor;
                float _SnowScale;
                float _SnowPower;
                float _SnowBrightness;
                float _VertexOffset;
                float _Smoothness;
                float4 _RenderTex_ST;
            CBUFFER_END

            TEXTURE2D(_RenderTex);
            SAMPLER(sampler_RenderTex);

            float hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float valueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);

                float a = hash21(i + float2(0, 0));
                float b = hash21(i + float2(1, 0));
                float c = hash21(i + float2(0, 1));
                float d = hash21(i + float2(1, 1));

                float x1 = lerp(a, b, u.x);
                float x2 = lerp(c, d, u.x);
                return lerp(x1, x2, u.y);
            }

            float fbm(float2 p)
            {
                float n = 0.0;
                float amp = 0.5;
                float freq = 1.0;

                [unroll]
                for (int o = 0; o < 3; o++)
                {
                    n += amp * valueNoise(p * freq);
                    freq *= 2.0;
                    amp *= 0.5;
                }
                return saturate(n);
            }

            float computeSnowMask(float2 uv)
            {
                float n = fbm(uv * _SnowScale);
                n = pow(saturate(n), max(0.0001, _SnowPower));
                n *= _SnowBrightness;
                return n;
            }

            float computeInteraction(float2 uv)
            {
                float2 ruv = TRANSFORM_TEX(uv, _RenderTex);
                float rt = SAMPLE_TEXTURE2D_LOD(_RenderTex, sampler_RenderTex, ruv, 0).r;
                return 1.0 - rt;
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vertShadow(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float snow = computeSnowMask(IN.uv);
                float interact = computeInteraction(IN.uv);
                float heightMask = snow + interact;

                float3 posOS = IN.positionOS.xyz;
                posOS.y += heightMask * _VertexOffset;

                // URP shadow caster transform (with bias)
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);
                float3 positionWS = TransformObjectToWorld(posOS);

                float4 positionCS =
                    TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _MainLightPosition.xyz));
                OUT.positionCS = positionCS;
                return OUT;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}