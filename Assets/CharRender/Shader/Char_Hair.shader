Shader "URPRender/Char_Hair"
{
    Properties
    {
        [Header(BaseInfo)]
        _BaseColor("BaseColor",Color) = (1,1,1,1)

        [Header(PBR Term)]
        _RoughnessAjustment("RoughnessAjustment",Range(-1,1)) = 0

        [Header(Dir SPECULAR)]
        _AnisoMap("AnisoMap",2D) = "white" {}
        _SpecularIntensity("SpecularIntensity",Range(0.01,2)) = 1

        _Expose1("Expose1",Range(0,1)) = 0.2
        _SpecColor1("SpecColor1",Color) = (1,1,1,1)
        _SpecNoise1("SpecNoise1",float) = 1
        _SpecOffset1("SpecOffset1",float) = 1

        _Expose2("Expose2",Range(0,1)) = 0.2
        _SpecColor2("SpecColor2",Color) = (1,1,1,1)
        _SpecNoise2("SpecNoise2",float) = 1
        _SpecOffset2("SpecOffset2",float) = 1


        [Header(Env SPECULAR)]
        _CubeMap("CubeMap",CUBE) = "white"{}
        _EnvSpeExpose("EnvSpeExpose",float) = 1
        _Tint("Tint",Color) = (1,1,1,1)
		_Rotate("Rotate",Range(0,360)) = 0
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Opaque"
            "RenderPipeline" = "UniversalPipeline"
            "LightMode" = "UniversalForward"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile __ DirDiffuse_ON
            #pragma multi_compile __ DirSpec_ON
            #pragma multi_compile __ EnvDiffuse_ON
            #pragma multi_compile __ EnvSpec_ON

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderGraphFunctions.hlsl"
            #define smp _linear_Repeat

            CBUFFER_START(UnityPerMaterial)
            SAMPLER(smp);
            half4 _BaseColor;

            half _RoughnessAjustment;

            //SPECULAR
            TEXTURE2D(_AnisoMap);
            half4 _AnisoMap_ST;
            half _SpecularIntensity;

            half _Expose1;
            half4 _SpecColor1;
            half _SpecNoise1;
            half _SpecOffset1;

            half _Expose2;
            half4 _SpecColor2;
            half _SpecNoise2;
            half _SpecOffset2;

            TEXTURECUBE(_CubeMap);
            float4 _CubeMap_HDR;
            float _EnvSpeExpose;
			SAMPLER(sampler_CubeMap);
            CBUFFER_END

            struct Attributes
            {
                float4 posOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : Normal;
                float4 tangent: TANGENT;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 posCS : SV_POSITION;

                float3 normal_world : TEXCOORD1;
                float3 pos_world : TEXCOORD2;
                float3 tan_world : TEXCOORD3;
                float3 binnor_world : TEXCOORD4;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.posCS = TransformObjectToHClip(v.posOS.xyz);
                o.uv = v.uv;
                o.pos_world = TransformObjectToWorld(v.posOS.xyz);

                //输入物体空间法线数据
				VertexNormalInputs normalInputs = GetVertexNormalInputs(v.normal.xyz,v.tangent);

                o.normal_world = normalInputs.normalWS;

                o.tan_world = normalInputs.tangentWS;

                o.binnor_world = normalInputs.bitangentWS;

                return o;
            }

            half4 frag (Varyings i) : SV_Target
            {
                //base color
                half3 base_col = _BaseColor.rgb;
                half3 spec_col = _BaseColor.rgb;
                half roughness = _RoughnessAjustment;

                //Lighting
                Light light = GetMainLight();
                half3 light_dir = normalize(light.direction);
                half3 light_color = light.color;

                //Dir
                half3 normal_dir = normalize(i.normal_world);
                half3 view_dir = normalize(_WorldSpaceCameraPos.xyz - i.pos_world);
                half3 half_dir = normalize(light_dir + view_dir);
                half3 tangent_dir = normalize(i.tan_world);
                half3 binormal_dir = normalize(i.binnor_world);

                //直接光的漫反射
                half diff_term = max(0.0,dot(normal_dir,light_dir));
                half half_lambert = diff_term * 0.5 + 0.5;

                #if DirDiffuse_ON
                half3 dir_diffuse = half_lambert * _BaseColor.rgb * light_color;
                #else
                half3 dir_diffuse = half3(0,0,0);
                #endif

                //直接光的镜面反射
                half2 uv_aniso = i.uv * _AnisoMap_ST.xy + _AnisoMap_ST.zw;
                half aniso_noise = SAMPLE_TEXTURE2D(_AnisoMap,smp,i.uv).r - 0.5;
                half aniso_noise_r = SAMPLE_TEXTURE2D(_AnisoMap,smp,i.uv).r * 0.5 + 0.5;

                half NdotH = dot(normal_dir,half_dir);
                half TdotH = dot(tangent_dir,half_dir);

                half NdotV = saturate(dot(normal_dir,view_dir));
                half aniso_atten = saturate(sqrt(saturate(half_lambert / NdotV)));

                //spec1
                half3 spec_color1 = _SpecColor1.rgb + base_col;
                half3 aniso_offset1 = normal_dir * (aniso_noise * _SpecNoise1 + _SpecOffset1);
                half3 binormal_dir1 = normalize(binormal_dir + aniso_offset1);
                half BdotH1 = dot(binormal_dir1,half_dir) / _Expose1;

                //half3 spec_term1 = sqrt(1.0 - BdotH1 * BdotH1);
                half3 spec_term1 = exp(-(TdotH * TdotH + BdotH1 * BdotH1) / (1.0 + NdotH));
                half3 dir_specular1 = spec_term1 * aniso_atten * spec_color1 * light_color;

                //spec2
                half3 spec_color2 = _SpecColor2.rgb + base_col;
                half3 aniso_offset2 = normal_dir * (aniso_noise * _SpecNoise2 + _SpecOffset2);
                half3 binormal_dir2 = normalize(binormal_dir + aniso_offset2);
                half BdotH2 = dot(binormal_dir2,half_dir) / _Expose2;
                half3 spec_term2 = exp(-(TdotH * TdotH + BdotH2 * BdotH2) / (1.0 + NdotH));
                half3 dir_specular2 = spec_term2 * aniso_atten * spec_color2 * light_color;


                #if DirSpec_ON
                half3 dir_specular = dir_specular1 + dir_specular2;
                #else
                half3 dir_specular = half3(0,0,0);
                #endif


                //间接光的高光反射
                half3 reflect_dir = reflect(-view_dir, normal_dir);
                roughness = roughness * (1.7 - 0.7 * roughness);
				float mip_level = roughness * 6.0;

                half4 color_cubemap = SAMPLE_TEXTURECUBE_LOD(_CubeMap, sampler_CubeMap, reflect_dir,mip_level);
				half3 env_color = DecodeHDREnvironment(color_cubemap, _CubeMap_HDR);//确保在移动端能拿到HDR信息
				
                #if EnvSpec_ON
                half3 env_spe = env_color * spec_col * half_lambert * aniso_noise_r * _EnvSpeExpose;
                #else
                half3 env_spe = half3(0,0,0);
                #endif


                half3 final_color = dir_specular + dir_diffuse + env_spe;

                return half4(final_color,1.0);
            }
            ENDHLSL
        }
    }
}
