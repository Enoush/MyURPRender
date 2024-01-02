Shader "URPRender/Char_Body"
{
    Properties
    {
        [Header(BaseInfo)]
        _BaseMap ("BaseMap", 2D) = "white" {}
        _CompMap ("CompMap", 2D) = "white" {}
        _NormalMap ("NormalMap", 2D) = "bump" {}

        [Header(SSS)]
        _SSSColor("SSSColor",Color) = (0.1,0.1,0.1,0.1)
        _SkinLut("SkinLut",2D) = "white"{}
        _SSSOffset("LutOffset",Range(-1,1)) = 0.5

        [Header(PBR Term)]
        _MetalAjustment("MetalAjustment",Range(-1,1)) = 0
        _RoughnessAjustment("RoughnessAjustment",Range(-1,1)) = 0
 
        [Header(Dir SPECULAR)]
		_Expose("Expose",Float) = 1.0
        _SpecularIntensity("SpecularIntensity",Range(0.01,5)) = 1

        [Header(Env SPECULAR)]
        _CubeMap("_CubeMap",CUBE) = "white"{}
        _Tint("Tint",Color) = (1,1,1,1)
		_Rotate("Rotate",Range(0,360)) = 0

        [HideInInSpector]custom_SHAr("Custom SHAr", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHAg("Custom SHAg", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHAb("Custom SHAb", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHBr("Custom SHBr", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHBg("Custom SHBg", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHBb("Custom SHBb", Vector) = (0, 0, 0, 0)
		[HideInInSpector]custom_SHC("Custom SHC", Vector) = (0, 0, 0, 1)
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
            
            #pragma multi_cmpile __ DirDiffuse_ON
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
            TEXTURE2D(_BaseMap);
            TEXTURE2D(_CompMap);
            TEXTURE2D(_NormalMap);
            TEXTURE2D(_SkinLut);

            half _MetalAjustment;
            half _RoughnessAjustment;

            half4 _SSSColor;
            half _SSSOffset;

            half _SpecularIntensity;

            half _Expose;
            //SH
            half4 custom_SHAr;
			half4 custom_SHAg;
			half4 custom_SHAb;
			half4 custom_SHBr;
			half4 custom_SHBg;
			half4 custom_SHBb;
			half4 custom_SHC;


            TEXTURECUBE(_CubeMap);
            float4 _CubeMap_HDR;
			SAMPLER(sampler_CubeMap);
            CBUFFER_END

            float3 custom_sh(float3 normal_dir)
            {
                float4 normalForSH = float4(normal_dir, 1.0);
				//SHEvalLinearL0L1
				half3 x;
				x.r = dot(custom_SHAr, normalForSH);
				x.g = dot(custom_SHAg, normalForSH);
				x.b = dot(custom_SHAb, normalForSH);

				//SHEvalLinearL2
				half3 x1, x2;
				// 4 of the quadratic (L2) polynomials
				half4 vB = normalForSH.xyzz * normalForSH.yzzx;
				x1.r = dot(custom_SHBr, vB);
				x1.g = dot(custom_SHBg, vB);
				x1.b = dot(custom_SHBb, vB);

				// Final (5th) quadratic (L2) polynomial
				half vC = normalForSH.x*normalForSH.x - normalForSH.y*normalForSH.y;
				x2 = custom_SHC.rgb * vC;

				float3 sh = max(float3(0.0, 0.0, 0.0), (x + x1 + x2));
				sh = pow(sh, 1.0 / 2.2);

                return sh;
            }

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
                half4 albedo_col_gamma = SAMPLE_TEXTURE2D(_BaseMap,smp, i.uv);
                half4 albedo_col = pow(albedo_col_gamma,2.2);

                half4 comp_mask = SAMPLE_TEXTURE2D(_CompMap,smp,i.uv);
                half4 pack_normal = SAMPLE_TEXTURE2D(_NormalMap,smp,i.uv);

                half metal = saturate(comp_mask.g + _MetalAjustment);
                half roughness = saturate(comp_mask.r + _RoughnessAjustment);

                half skin_area = 1.0 - comp_mask.b;//皮肤为1

                half3 base_col = albedo_col.rgb * (1-metal);//固有色
                half3 spec_col = lerp(0.0,albedo_col.rgb,metal);//高光颜色

                //Lighting
                Light light = GetMainLight();
                half3 light_dir = normalize(light.direction);
                half3 light_color = light.color;

                //Dir
                half3 normal_dir = normalize(i.normal_world);
                half3 view_dir = normalize(_WorldSpaceCameraPos.xyz - i.pos_world);
                half3 half_dir = normalize(light_dir + view_dir);

                float3x3 TBN = float3x3(normalize(i.tan_world),normalize(i.binnor_world),normal_dir);
                half3 normal_tan = UnpackNormal(pack_normal);
                normal_dir = normalize(mul(normal_tan.xyz,TBN));

                //直接光的漫反射
                half diff_term = max(0.0,dot(normal_dir,light_dir));
                half half_lambert = diff_term * 0.5 + 0.5;
                half3 common_diffuse = diff_term * base_col * light_color;
                half2 uv_lut = half2(saturate(half_lambert + _SSSOffset),1);
                half4 lut_color_gama = SAMPLE_TEXTURE2D(_SkinLut,smp,uv_lut);
                half4 lut_color = pow(lut_color_gama,2.2);
                half3 sss_diffuse = lut_color.rgb * base_col * light_color * half_lambert;
                
                #if DirDiffuse_ON
                half3 dir_diffuse = lerp(common_diffuse,sss_diffuse,skin_area);
                #else
                half3 dir_diffuse = half3(0,0,0);
                #endif

                //直接光的镜面反射
                half NdotH = dot(normal_dir,half_dir);
                half smoothness = 1 - roughness;
                half expose = lerp(1,_Expose,smoothness);
                half spe_term = pow(max(0,NdotH),expose) * _SpecularIntensity;

                half3 spe_skin_color = lerp(spec_col,0.2,skin_area);

                #if DirSpec_ON
                half3 dir_specular = spe_term * spe_skin_color * light_color;
                #else
                half3 dir_specular = half3(0,0,0);
                #endif

                //间接光的漫反射
                float3 env_diffuse = custom_sh(normal_dir) * base_col * half_lambert;

                #if EnvDiffuse_ON
                env_diffuse = lerp(env_diffuse * 0.5,env_diffuse,skin_area);
                #else
                env_diffuse = half3(0,0,0);
                #endif

                //间接光的高光反射
                half3 reflect_dir = reflect(-view_dir, normal_dir);
                roughness = roughness * (1.7 - 0.7 * roughness);
				float mip_level = roughness * 6.0;
				//half4 color_cubemap = texCUBElod(_CubeMap,float4(reflect_dir,mip_level));
                half4 color_cubemap = SAMPLE_TEXTURECUBE_LOD(_CubeMap, sampler_CubeMap, reflect_dir,mip_level);
				half3 env_color = DecodeHDREnvironment(color_cubemap, _CubeMap_HDR);//确保在移动端能拿到HDR信息
                
                #if EnvSpec_ON
				half3 env_spe = env_color * spec_col * half_lambert *_SpecularIntensity;
                #else
                half3 env_spe = half3(0,0,0);
                #endif

                half3 final_color = dir_specular + dir_diffuse  + env_spe + env_diffuse;

                final_color = pow(final_color,1.0/2.2);

                return half4(final_color.rgb,1.0);
            }
            ENDHLSL
        }
    }
}
