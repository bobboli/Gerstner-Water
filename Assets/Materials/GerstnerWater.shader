// Refer to http://www.manew.com/thread-112638-1-1.html
Shader "Custom/GerstnerWater"
{
	Properties
	{
		_MainTex ("Texture", 2D) = "white" {}
        _SizeX("Mesh size X in world unit", Float) = 40
        _SizeY("Mesh size Y in world unit", Float) = 40
        _Amplitude("Wave amplitude", Float) = 1
		_Wavelength("Wavelength", Float) = 1
		_SteepnessScale("Steepness Scale", Float) = 1
		_Velocity("Wave velocity vector (only xy is used)", Vector) = (1, 1, 0, 0)
		_ColWarm("Warm color", Color) = (0.3, 0.3, 0.8, 1.0)
		_ColCold("Cold color", Color) = (0.1, 0.1, 0.9, 1.0)
		_ColDistinctionRate("Color Distinction Rate", Range(0, 1)) = 0.5
		_ColDeep("Deep water color", Color) = (0.1, 0.1, 0.9, 1.0)
		_ColSurf("Surface water color", Color) = (0.1, 0.1, 0.9, 1.0)
		_SkyEnv("Sky Environment Cubemap", Cube) = ""{}
		_R0("Minimum Fresnel Reflection Factor", Range(0, 1)) = 0.2
		_LightDir("Light source direction", Vector) = (1, 1, 1, 0)
		_Shininess("Specular Shininess", Range(0, 3)) = 0.26

        _BumpStrength("Bump Strength", Range(0,1)) = 0.5
		_TexNormal("Bump Normal Texture", 2D) = ""{}
		_UVScale("UV tiling", Float) = 1
		_UVOffsetScale("Bump map UV offset scale", Float) = 1
		_AmplitudeMask("Amplitude mask", 2D) = ""{}
        _UvOffset("UV Offset", Vector) = (0,0,0,0)

		


	}
	SubShader
	{
		Tags { "RenderType"="Transparent" }
		Blend One SrcAlpha

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			
			#include "UnityCG.cginc"

			struct VertexIn
			{
				float3 posL : POSITION;  // 
				//	float2 uv : TEXCOORD0;  // We actually rely on uv to compute wave disturbance.
			};

			struct VertexOut
			{
				float4 posH : SV_POSITION;
                fixed3 col : TEXCOORD0; // per vertex shading
                float3 posL : TEXCOORD1;
				float3 normalL : TEXCOORD2;
			};

			sampler2D _MainTex;
            float _SizeX;
            float _SizeY;
            float _Amplitude;
			float _SteepnessScale;
			float2 _Velocity;
			float _Wavelength;
			float3 _LightDir;
			float _Shininess;
			float3 _ColCold;
			float3 _ColWarm;
			float _ColDistinctionRate;
			float3 _ColDeep;
			float3 _ColSurf;
			samplerCUBE _SkyEnv;
			sampler2D _TexNormal;
			SamplerState samplerWrap{
				Filter = MIN_MAG_MIP_LINEAR;
				AddressU = Wrap;
    			AddressV = Wrap;
			};




			float _BumpStrength;

			float _R0;
			float _UVScale;
			float _UVOffsetScale;
			float2 _UvOffset;
			sampler2D _AmplitudeMask;



			float4 _MainTex_ST;

			#define pi 3.14159
			#define sqrt3 1.73205
			#define ln2 0.69315
			#include "snoise.cginc"

			float2 GetWavevector(float2 velocity, float wavelength)
			{
				return 2*pi/ wavelength *  normalize(velocity) ;
			}

	#define AUTO_AMPLITUDE 0
            float3 GerstnerWaveOffset(float2 xy, float2 wavevector, float omega, float phase0, float amplitude, float steepness)
            {

				float phase = dot(wavevector, xy)  - omega*_Time.y + phase0;  // _Time = (t/20, t, t*2, t*3)
				#if AUTO_AMPLITUDE
				amplitude = exp(sin(phase)-1.0) * _Amplitude;
				#endif
				
                // Note: steepness should be less than 1/(length(wavevector) * amplitude)
				steepness = min(steepness, 1.0 / (length(wavevector)* amplitude));
                float2 dir = normalize(wavevector);

                float2 dxdy = steepness * amplitude * cos(phase) * dir;
               // float dz = 10*sin(10*_Time.y);// amplitude * sin(phase);
			    float dz = amplitude * sin(phase); 
                return float3(dxdy, dz);
            }


            float3 GerstnerWaveNormal(float2 xyDisturbed, float2 wavevector, float omega, float phase0, float amplitude, float steepness)
            {
				steepness = min(steepness, 1.0 / (length(wavevector)* amplitude));
                float phase = dot(wavevector, xyDisturbed) - omega * _Time.y + phase0;
                float2 nxny = -amplitude * cos(phase) * wavevector;
                float nz = -steepness * amplitude * length(wavevector) * sin(phase);
                return float3(nxny, nz);
            }


			
			float3 Gerstner(float a, float b, float c , float k)
			{
				float t = _Time.y;
				float e = 2.71828;
				float x = a + ((pow(e,k*b)/k) * sin(k*(a+c*t)));
				float z = b - ((pow(e,k*b)/k) * cos(k*(a+c*t)));
				return float3(x-a,0,z);
			}

			float3 Rotate(float3 pos, float degrees)
			{
				float sinX = sin ( degrees * 1/180 * 3.14159 );
				float cosX = cos ( degrees * 1/180 * 3.14159 );
				float2x2 rotationMatrix = float2x2( cosX, -sinX, sinX, cosX);
				pos.xy = mul(pos.xy, rotationMatrix);
				return pos;
			}

			float2 GetUV(float2 xy)
			{
				return saturate(xy / float2(_SizeX, _SizeY) + 0.5);
			}



			float2 RotateVector2D(float2 xy, float degrees)
			{
				float radians = degrees * 1/180 * 3.14159;
				float sinx = sin(radians);
				float cosx = cos(radians);
				return float2(cosx * xy.x - sinx * xy.y, sinx * xy.x + cosx * xy.y);
			}

			struct WaveOut{
				float3 dxdydz;
				float3 nxnynz;
			};

			void InitParams(out float rot, out float weight, out float omega, out float speed)
			{
				rot = 0.0;
				weight = 1.0;
				speed = length(_Velocity);
				omega = 2*pi*speed / _Wavelength;
			}

			void IterParams(inout float rot, inout float weight, inout float omega, inout float speed)
			{
				// rot = -rot;
				// if(rot > 0.0)
				// {
				// 	rot += 90.0;
				// }
				rot += 50.0;

				weight = lerp(weight, 0.0, 0.1);
				omega *= 1.18;
				speed *= 1.07;
			}

			WaveOut getwaves(float2 xy, int iterations){

				_Velocity.y *= -1;	
				
				float2 mainWaveDir = normalize(_Velocity);
				 // For some reason... flipped. Because our mesh vertex winding order does not match with Unity, the mesh is rotated.
				 // Also, because of isometric rot of 30 degrees, multiply by 2 / sqrt3 (deprecated)
				 mainWaveDir.y *= -2 / sqrt3;

				float noise = snoise(xy/10.0)*0.5+0.5;
				float2 uv = GetUV(xy);

				WaveOut waveout;
				waveout.dxdydz = 0.0;
				waveout.nxnynz = 0.0;

				float rot;
				float weight;
				float omega;
				float speed;

				float weight_total = 0.0;
				InitParams(rot, weight, omega, speed);
				for(int i=0;i<iterations;i++){
					float2 dir = RotateVector2D(mainWaveDir, rot);
					float2 wavevec = GetWavevector(dir * speed, 2 * pi * speed / omega);
					waveout.dxdydz += GerstnerWaveOffset(xy, wavevec, omega , noise* cos(_Time.y), _Amplitude * weight * (1.0-tex2Dlod(_AmplitudeMask, float4(uv, 0, 0)).x) /*(cos(_Time.y) * 0.5 + 0.5) *//*TODO*/, _SteepnessScale);
					weight_total += weight;
					IterParams(rot, weight, omega, speed);
				}
				waveout.dxdydz /= weight_total;

				InitParams(rot, weight, omega, speed);
				float2 xy_disturbed = xy + waveout.dxdydz.xy;
				for(int i=0;i<iterations;i++){
					float2 dir = RotateVector2D(mainWaveDir, rot);
					float2 wavevec = GetWavevector(dir * speed, 2 * pi * speed / omega);
					waveout.nxnynz += GerstnerWaveNormal(xy_disturbed, wavevec, omega , noise* cos(_Time.y), _Amplitude * weight * (1.0-tex2Dlod(_AmplitudeMask, float4(uv, 0, 0)).x)  /*(cos(_Time.y) * 0.5 + 0.5) *//*TODO*/, _SteepnessScale);
					IterParams(rot, weight, omega, speed);
				}
				waveout.nxnynz /= weight_total;
				waveout.nxnynz.z += 1.0;
				waveout.nxnynz = normalize(waveout.nxnynz);

				return waveout;
			}

			float3 FresnelR(float3 normal, float3 viewDir, float R0){
				// Schlick's Fresnel approximation
				float NdotV = dot(normal, viewDir);
				if(NdotV < 0 ) NdotV = -NdotV; // This is a hack, in case when looking from back of the surface by mistake
            	float oneMinusNdotV5 = pow(1.0 - NdotV, 5.0);
				return lerp(oneMinusNdotV5, 1, R0);
			}

			float3 Specular(float3 viewDir, float3 lightDir, float3 normal){
				// https://www.gamedev.net/articles/programming/graphics/rendering-water-as-a-post-process-effect-r2642/
				half dotSpec = dot(reflect(-viewDir, normal), lightDir) * 0.5 + 0.5;  // Half-Lambertian like
				//return half3(dotSpec, dotSpec, dotSpec);
				half3 colSpec = saturate(lightDir.z) * ((pow(dotSpec, 512.0)) * (_Shininess * 1.8 + 0.2)); // lightDir.z is consine foreshortten term
				colSpec += colSpec * 25 * saturate(_Shininess - 0.05);	
				return colSpec;

			}

			VertexOut vert (VertexIn vin)
			{
				VertexOut vout;

				



                float2 xy = vin.posL.xy; // vin.uv * float2(_SizeX, _SizeY);


				//float noise = snoise(vin.posL.xy)*0.5+0.5; // Generate a simplex noise for this position

                #define numWaves 4


                static const float amplitudeScale[numWaves] = {1.0, 0.8, 0.5, 0.1};
                static const float velocityScale[numWaves] = {1.0, 0.8, 0.5, 0.1};
				static const float velocityRot[numWaves] = {0,-45,40,45};//{0, 60, 30, -30};
				static const float wavelengths[numWaves] = {1.0, 0.8, 0.5, 0.1};
 
               //static const float omega[numWaves] = {10, 8, 5, 1};
                static const float phase0[numWaves] = {0.0, 5.0, 8.0, 14.0};
                static const float steepness[numWaves] = {1.0, 0.8, 0.5, 0.1};

				//noise = 1.0;

                float3 dxdydz = float3(0, 0, 0);
                // Disturb position.
                // for(int i = 0; i < 1; ++i)
                // {
				// 	float wavelength = _Wavelength * wavelengths[i];
				// 	float2 velocity = RotateVector2D(_Velocity.xy, velocityRot[i] * noise) * velocityScale[i] * noise;
				// 	float2 wavevector = GetWavevector( velocity, wavelength);
                //     dxdydz += GerstnerWaveOffset(xy, wavevector, 
                //        2*pi/wavelength*length(velocity) , phase0[i], _Amplitude * amplitudeScale[i] * 1, steepness[i] * _SteepnessScale);
                // }


				WaveOut wave = getwaves(xy, 15);

                // Note: the mesh must lie in XY plane in local space.
                vout.posL = vin.posL + wave.dxdydz;
                vout.posH = UnityObjectToClipPos(float4(vout.posL, 1.0));
				vout.normalL = wave.nxnynz;

				float height = (1.0-tex2Dlod(_AmplitudeMask, float4(GetUV(xy), 0, 0)).x);
				float alpha = - ln2 / log(_ColDistinctionRate);  // factor = height ^ alpha, 1/2 = distinctionrate ^ alpha
				float3 colWater = lerp(_ColCold, _ColWarm, exp2(log2(height)*alpha));
				vout.col = colWater;

				//vout.col = noise;

				// per vertex shading
				// float3 lightDir = normalize(_LightDir.xyz);
				// lightDir.y *= -1;

				// float t = (dot(lightDir, vout.normalL) + 1.0) / 2.0;
				// vout.col = lerp(_ColCold.rgb, _ColWarm.rgb, t);

				// float height = vout.posL.z / _Amplitude;

				// float3 colWater = height < 0.0? _ColCold : lerp(_ColCold, _ColWarm, height);
				// if(height < 0){
				// 	colWater = lerp(_ColDeep, _ColSurf, height + 1.0);
				// }
				// else if(height < 0.8){
				// 	colWater = lerp(_ColSurf, _ColCold, height / 0.8);
				// }
				// else{
				// 	colWater = _ColWarm;
				// }

				// colWater = lerp(_ColCold.rgb, _ColWarm.rgb, height * 0.5+0.5);
				// //colWater = height < 0.2 ? _ColCold : _ColWarm;

				// vout.col = colWater;



				

				return vout;



                // // Disturb normal.
                // vout.normL = float3(0, 0, 1);
                // for(int i = 0; i < numWaves; ++i){
                //     //vout.normL += GerstnerWaveNormal(xy + dxdydz.xy, RotateVector2D(dxdydz.xy * wavevectorScale[i], velocityRot[i]*noise), 
                //     //    omega[i], phase0[i], _Amplitude * amplitudeScale[i] * noise, steepness[i] * _SteepnessScale);
                // }

				// // Per vertex shading.

				// return vout;
			}
			
			float4 frag (VertexOut vout) : SV_Target
			{
				float2 uv = GetUV(vout.posL.xy);
				// return fixed4(uv, 0,0);  // Uncomment here to see UV.

				float2 velocity = _Velocity;
				velocity.x *= -1; // Note here, uv offset is contrary to the velocity
				velocity.y *= 2 / sqrt3;
				float3 normal = normalize(lerp(vout.normalL, UnpackNormal(tex2D(_TexNormal, uv*_UVScale - _UvOffset * _UVOffsetScale)), _BumpStrength)); // _Time.y * velocity*_UVOffsetScale)), _BumpStrength));

				

				float3 lightDir = normalize(_LightDir);

				float3 viewDir = float3(0.0, -0.5, 0.5*sqrt3);
				float fresnelR = FresnelR(normal, viewDir, _R0);


				float3 viewRefl = reflect(-viewDir, normal);
				if(viewRefl.z < 0.0){
					//viewRefl = reflect(viewRefl, float3(0,0,1));
					//fresnelR *= FresnelR(normal, viewRefl, _R0);
				}

				float3 colSky = saturate(texCUBE(_SkyEnv, viewRefl).rgb);
				float3 colSpec = Specular(viewDir, lightDir, normal);

				//float t = (dot(lightDir, vout.normalL) + 1.0) / 2.0;
				//vout.col = lerp(_ColCold.rgb, _ColWarm.rgb, t);

				float height = vout.posL.z / _Amplitude;

				//float3 colWater = height < 0.0? _ColCold : lerp(_ColCold, _ColWarm, height);



				// if(height < 0){
				// 	colWater = lerp(_ColDeep, _ColSurf, height + 1.0);
				// }
				// else if(height < 0.8){
				// 	colWater = lerp(_ColSurf, _ColCold, height / 0.8);
				// }
				// else{
				// 	colWater = _ColWarm;
				// }


				// float3 colWater = lerp(_ColCold.rgb, _ColWarm.rgb, height * 0.5+0.5);

				float3 colWater = (1-fresnelR)*vout.col + fresnelR*colSky + colSpec;
				return float4(colWater, 1-fresnelR);

				//return float4(vout.normalL*0.5+0.5, 1.0 ); // For debugging - show normals


				float h = vout.posL.z / _Amplitude * 0.5 + 0.5; 
				float col = h;
				return fixed4(0.0, 0.0, col,1.0);
                return fixed4(vout.posL.x/20 ,vout.posL.y/20 , 0.0, 1.0);
			}
			ENDCG
		}
	}
}