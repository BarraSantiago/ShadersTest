Shader "Custom/InteractiveSnowURP_SimpleLit"
{
    Properties
    {
        [HDR]_SnowColor("Snow Color", Color) = (1,1,1,1)

        _SnowScale("Snow Scale", Float) = 80
        _SnowPower("Snow Power", Float) = 2
        _SnowBrightness("Snow Brightness", Float) = 1

        _VertexOffset("Vertex Offset", Float) = 0.05

        _RenderTex("Render Texture", 2D) = "black" {}
        _RenderTex_ST("Render Texture ST", Vector) = (1,1,0,0)
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
            Name "Forward"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            #pragma target 3.0
            #pragma vertex vert
            #pragma fragment frag

            // Sombras principales (si el renderer las tiene)
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _SnowColor;
                float _SnowScale;
                float _SnowPower;
                float _SnowBrightness;
                float _VertexOffset;
                float4 _RenderTex_ST;
            CBUFFER_END

            TEXTURE2D(_RenderTex);
            SAMPLER(sampler_RenderTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float4 shadowCoord : TEXCOORD3;
            };

            // --- Noise baratito ---
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

                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            float fbm3(float2 p)
            {
                float n = 0.0;
                float amp = 0.5;
                float freq = 1.0;

                [unroll] for (int o = 0; o < 3; o++)
                {
                    n += amp * valueNoise(p * freq);
                    freq *= 2.0;
                    amp *= 0.5;
                }
                return saturate(n);
            }

            float computeSnow(float2 uv)
            {
                float n = fbm3(uv * _SnowScale);
                n = pow(saturate(n), max(0.0001, _SnowPower));
                n *= _SnowBrightness;
                return n;
            }

            float computeInteraction(float2 uv)
            {
                float2 ruv = uv * _RenderTex_ST.xy + _RenderTex_ST.zw;
                float rt = SAMPLE_TEXTURE2D_LOD(_RenderTex, sampler_RenderTex, ruv, 0).r;
                return 1.0 - rt; // One Minus
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                float snow = computeSnow(IN.uv);
                float interact = computeInteraction(IN.uv);

                float heightMask = snow + interact;

                // Desplazar POR NORMAL (funciona en cubos, pendientes, lo que sea)
                float3 posOS = IN.positionOS.xyz;
                posOS += IN.normalOS * (heightMask * _VertexOffset);

                VertexPositionInputs vp = GetVertexPositionInputs(posOS);
                OUT.positionCS = vp.positionCS;
                OUT.positionWS = vp.positionWS;

                OUT.normalWS = normalize(TransformObjectToWorldNormal(IN.normalOS));
                OUT.uv = IN.uv;

                OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float snow = computeSnow(IN.uv);
                half3 albedo = (half3)(_SnowColor.rgb * snow);

                // Luz principal URP
                Light mainLight = GetMainLight(IN.shadowCoord);
                half ndotl = saturate(dot(normalize(IN.normalWS), mainLight.direction));

                // Ambient SH (cielo/entorno)
                half3 ambient = SampleSH(normalize(IN.normalWS));

                half3 lit = albedo * (ambient + mainLight.color * ndotl * mainLight.shadowAttenuation);

                // Fog URP
                half fogFactor = ComputeFogFactor(IN.positionCS.z);
                lit = MixFog(lit, fogFactor);

                return half4(lit, 1);
            }
            ENDHLSL
        }

        // (Opcional) Para no romper compilación según versión,
        // no meto ShadowCaster custom aquí. Tendrás sombras “normales”,
        // pero NO seguirán el displacement. Cuando todo funcione, lo añadimos.
    }
}