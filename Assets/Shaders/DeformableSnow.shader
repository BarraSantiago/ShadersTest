Shader "Custom/DeformableSnow"
{
    Properties
    {
        _SnowColor ("Snow Color", Color) = (1,1,1,1)
        _SnowScale ("Snow Scale", Float) = 80
        _SnowPower ("Snow Power", Float) = 3
        _SnowBrightness ("Snow Brightness", Float) = 2.8
        _Displacement ("Vertex Offset", Float) = 0.025
        _HeightMap ("Render Texture", 2D) = "white" {}
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"
        }
        LOD 100

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
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float fogFactor : TEXCOORD1;
            };

            TEXTURE2D(_HeightMap);
            SAMPLER(sampler_HeightMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _SnowColor;
                float _SnowScale;
                float _SnowPower;
                float _SnowBrightness;
                float _Displacement;
                float4 _HeightMap_ST;
            CBUFFER_END

            // Simple Noise function (2D)
            float SimpleNoise(float2 uv)
            {
                return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
            }

            // Better noise function using multiple octaves
            float PerlinNoise(float2 uv)
            {
                float2 i = floor(uv);
                float2 f = frac(uv);
                f = f * f * (3.0 - 2.0 * f);

                float a = SimpleNoise(i);
                float b = SimpleNoise(i + float2(1.0, 0.0));
                float c = SimpleNoise(i + float2(0.0, 1.0));
                float d = SimpleNoise(i + float2(1.0, 1.0));

                return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
            }

            Varyings vert(Attributes input)
            {
                Varyings output;

                // Sample render texture (inverted for depressions)
                float renderTexSample = 1.0 - SAMPLE_TEXTURE2D_LOD(_HeightMap, sampler_HeightMap, input.uv, 0).r;

                // Generate procedural noise
                float2 scaledUV = input.uv * _SnowScale;
                float noise = PerlinNoise(scaledUV);

                // Apply snow power and brightness
                noise = pow(noise, _SnowPower) * _SnowBrightness;

                // Combine noise with render texture
                float combinedHeight = noise + renderTexSample;

                // Vertex displacement along normal
                float3 displacedPosition = input.positionOS.xyz + input.normalOS * combinedHeight * _Displacement;

                output.positionCS = TransformObjectToHClip(displacedPosition);
                output.uv = input.uv;
                output.fogFactor = ComputeFogFactor(output.positionCS.z);

                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // Generate same noise for base color
                float2 scaledUV = input.uv * _SnowScale;
                float noise = PerlinNoise(scaledUV);
                noise = pow(noise, _SnowPower) * _SnowBrightness;

                // Apply snow color
                half4 color = _SnowColor * noise;

                // Apply fog
                color.rgb = MixFog(color.rgb, input.fogFactor);

                return color;
            }
            ENDHLSL
        }

        // Shadow casting pass
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode"="ShadowCaster"
            }

            HLSLPROGRAM
            #pragma vertex vertShadow
            #pragma fragment fragShadow

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct AttributesShadow
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct VaryingsShadow
            {
                float4 positionCS : SV_POSITION;
            };

            VaryingsShadow vertShadow(AttributesShadow input)
            {
                VaryingsShadow output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half4 fragShadow(VaryingsShadow input) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}