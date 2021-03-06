// Auf Myriadcoin spezialisierte Version von Groestl inkl. Bitslice

#include <stdio.h>
#include <memory.h>
#include "miner.h"
#include "cuda_helper.h"


// globaler Speicher für alle HeftyHashes aller Threads
__constant__ uint32_t pTarget[8]; // Single GPU
static uint32_t *d_outputHashes[MAX_GPUS];
static uint32_t *d_resultNonce[MAX_GPUS];

__constant__ uint32_t myriadgroestl_gpu_msg[20];

// muss expandiert werden
__constant__ uint32_t myr_sha256_gpu_constantTable[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};
__constant__ uint32_t myr_sha256_gpu_constantTable2[64] = {
	0xc28a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf374,
	0x649b69c1, 0xf0fe4786, 0x0fe1edc6, 0x240cf254, 0x4fe9346f, 0x6cc984be, 0x61b9411e, 0x16f988fa,
	0xf2c65152, 0xa88e5a6d, 0xb019fc65, 0xb9d99ec7, 0x9a1231c3, 0xe70eeaa0, 0xfdb1232b, 0xc7353eb0,
	0x3069bad5, 0xcb976d5f, 0x5a0f118f, 0xdc1eeefd, 0x0a35b689, 0xde0b7a04, 0x58f4ca9d, 0xe15d5b16,
	0x007f3e86, 0x37088980, 0xa507ea32, 0x6fab9537, 0x17406110, 0x0d8cd6f1, 0xcdaa3b6d, 0xc0bbbe37,
	0x83613bda, 0xdb48a363, 0x0b02e931, 0x6fd15ca7, 0x521afaca, 0x31338431, 0x6ed41a95, 0x6d437890,
	0xc39c91f2, 0x9eccabbd, 0xb5c9a0e6, 0x532fb63c, 0xd2c741c6, 0x07237ea3, 0xa4954b68, 0x4c191d76
};

__constant__ uint32_t myr_sha256_gpu_hashTable[8] = {
	0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };

__constant__ uint32_t myr_sha256_gpu_w2Table[64] = {
    0x80000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 
    0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000200,
    0x80000000, 0x01400000, 0x00205000, 0x00005088, 0x22000800, 0x22550014, 0x05089742, 0xa0000020,
    0x5a880000, 0x005c9400, 0x0016d49d, 0xfa801f00, 0xd33225d0, 0x11675959, 0xf6e6bfda, 0xb30c1549,
    0x08b2b050, 0x9d7c4c27, 0x0ce2a393, 0x88e6e1ea, 0xa52b4335, 0x67a16f49, 0xd732016f, 0x4eeb2e91,
    0x5dbf55e5, 0x8eee2335, 0xe2bc5ec2, 0xa83f4394, 0x45ad78f7, 0x36f3d0cd, 0xd99c05e8, 0xb0511dc7,
    0x69bc7ac4, 0xbd11375b, 0xe3ba71e5, 0x3b209ff2, 0x18feee17, 0xe25ad9e7, 0x13375046, 0x0515089d,
    0x4f0d0f04, 0x2627484e, 0x310128d2, 0xc668b434, 0x420841cc, 0x62d311b8, 0xe59ba771, 0x85a7a484 };

// 64 Register Variante für Compute 3.0
#include "groestl_functions_quad.cu"
#include "bitslice_transformations_quad.cu"

#define R(x, n)            ((x) >> (n))
#define Ch(x, y, z)        ((x & (y ^ z)) ^ z)
#define Maj(x, y, z)    ((x & (y | z)) | (y & z))
#define S0(x)            (ROTR32(x, 2) ^ ROTR32(x, 13) ^ ROTR32(x, 22))
#define S1(x)            (ROTR32(x, 6) ^ ROTR32(x, 11) ^ ROTR32(x, 25))
#define s0(x)            (ROTR32(x, 7) ^ ROTR32(x, 18) ^ R(x, 3))
#define s1(x)            (ROTR32(x, 17) ^ ROTR32(x, 19) ^ R(x, 10))

static __device__ void myriadgroestl_gpu_sha256(uint32_t *message)
{
    uint32_t W1[16];
    uint32_t W2[16];

    // Initialisiere die register a bis h mit der Hash-Tabelle
	uint32_t regs[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
	uint32_t hash[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };

#pragma unroll 16
    for(int k=0;k<16;k++)
        W1[k] = cuda_swab32(message[k]);

// Progress W1
#pragma unroll 16
    for(int j=0;j<16;j++)
    {
        uint32_t T1, T2;
        T1 = regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable[j] + W1[j];
        T2 = S0(regs[0]) + Maj(regs[0], regs[1], regs[2]);
        
        #pragma unroll 7
        for (int k=6; k >= 0; k--) regs[k+1] = regs[k];
        regs[0] = T1 + T2;
        regs[4] += T1;
    }

// Progress W2...W3
////// PART 1
#pragma unroll 2
    for(int j=0;j<2;j++)
        W2[j] = s1(W1[14+j]) + W1[9+j] + s0(W1[1+j]) + W1[j];
#pragma unroll 5
    for(int j=2;j<7;j++)
        W2[j] = s1(W2[j-2]) + W1[9+j] + s0(W1[1+j]) + W1[j];

#pragma unroll 8
    for(int j=7;j<15;j++)
        W2[j] = s1(W2[j-2]) + W2[j-7] + s0(W1[1+j]) + W1[j];

    W2[15] = s1(W2[13]) + W2[8] + s0(W2[0]) + W1[15];

    // Rundenfunktion
#pragma unroll 16
    for(int j=0;j<16;j++)
    {
        uint32_t T1, T2;
        T1 = regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable[j + 16] + W2[j];
        T2 = S0(regs[0]) + Maj(regs[0], regs[1], regs[2]);
        
        #pragma unroll 7
        for (int l=6; l >= 0; l--) regs[l+1] = regs[l];
        regs[0] = T1 + T2;
        regs[4] += T1;
    }

////// PART 2
#pragma unroll 2
    for(int j=0;j<2;j++)
        W1[j] = s1(W2[14+j]) + W2[9+j] + s0(W2[1+j]) + W2[j];
#pragma unroll 5
    for(int j=2;j<7;j++)
        W1[j] = s1(W1[j-2]) + W2[9+j] + s0(W2[1+j]) + W2[j];

#pragma unroll 8
    for(int j=7;j<15;j++)
        W1[j] = s1(W1[j-2]) + W1[j-7] + s0(W2[1+j]) + W2[j];

    W1[15] = s1(W1[13]) + W1[8] + s0(W1[0]) + W2[15];

    // Rundenfunktion
#pragma unroll 16
    for(int j=0;j<16;j++)
    {
        uint32_t T1, T2;
        T1 = regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable[j + 32] + W1[j];
        T2 = S0(regs[0]) + Maj(regs[0], regs[1], regs[2]);
        
        #pragma unroll 7
        for (int l=6; l >= 0; l--) regs[l+1] = regs[l];
        regs[0] = T1 + T2;
        regs[4] += T1;
    }

////// PART 3
#pragma unroll 2
    for(int j=0;j<2;j++)
        W2[j] = s1(W1[14+j]) + W1[9+j] + s0(W1[1+j]) + W1[j];
#pragma unroll 5
    for(int j=2;j<7;j++)
        W2[j] = s1(W2[j-2]) + W1[9+j] + s0(W1[1+j]) + W1[j];

#pragma unroll 8
    for(int j=7;j<15;j++)
        W2[j] = s1(W2[j-2]) + W2[j-7] + s0(W1[1+j]) + W1[j];

    W2[15] = s1(W2[13]) + W2[8] + s0(W2[0]) + W1[15];

    // Rundenfunktion
#pragma unroll 16
    for(int j=0;j<16;j++)
    {
        uint32_t T1, T2;
        T1 = regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable[j + 48] + W2[j];
        T2 = S0(regs[0]) + Maj(regs[0], regs[1], regs[2]);
        
        #pragma unroll 7
        for (int l=6; l >= 0; l--) regs[l+1] = regs[l];
        regs[0] = T1 + T2;
        regs[4] += T1;
    }

#pragma unroll 8
    for(int k=0;k<8;k++)
        hash[k] += regs[k];

    /////
    ///// Zweite Runde (wegen Msg-Padding)
    /////
#pragma unroll 8
    for(int k=0;k<8;k++)
        regs[k] = hash[k];

// Progress W1
#pragma unroll 
    for(int j=0;j<57;j++)
    {
		uint32_t T1, T2;
		T1 = regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable2[j];
		T2 = S0(regs[0]) + Maj(regs[0], regs[1], regs[2]);

#pragma unroll
		for (int k = 6; k >= 0; k--) regs[k + 1] = regs[k];
		regs[0] = T1 + T2;
		regs[4] += T1;
	}

	regs[3] += regs[7] + S1(regs[4]) + Ch(regs[4], regs[5], regs[6]) + myr_sha256_gpu_constantTable2[57];
	regs[2] += regs[6] + S1(regs[3]) + Ch(regs[3], regs[4], regs[5]) + myr_sha256_gpu_constantTable2[58];
	regs[1] += regs[5] + S1(regs[2]) + Ch(regs[2], regs[3], regs[4]) + myr_sha256_gpu_constantTable2[59];
	regs[0] += regs[4] + S1(regs[1]) + Ch(regs[1], regs[2], regs[3]) + myr_sha256_gpu_constantTable2[60];

	message[7] = cuda_swab32(hash[7] + regs[0]);
}

__global__ void __launch_bounds__(512, 2)
 myriadgroestl_gpu_hash_quad(uint32_t threads, uint32_t startNounce, uint32_t *hashBuffer)
{
    // durch 4 dividieren, weil jeweils 4 Threads zusammen ein Hash berechnen
    const uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x) >> 2;
    if (thread < threads)
    {
        // GROESTL
		uint32_t paddedInput[8];
		paddedInput[0] = myriadgroestl_gpu_msg[4 * 0 + (threadIdx.x & 3)];
		paddedInput[1] = myriadgroestl_gpu_msg[4 * 1 + (threadIdx.x & 3)];
		paddedInput[2] = myriadgroestl_gpu_msg[4 * 2 + (threadIdx.x & 3)];
		paddedInput[3] = myriadgroestl_gpu_msg[4 * 3 + (threadIdx.x & 3)];
		paddedInput[4] = myriadgroestl_gpu_msg[4 * 4 + (threadIdx.x & 3)];
		paddedInput[5] = 0;
		paddedInput[6] = 0;
		paddedInput[7] = 0;

		if((threadIdx.x & 3) == 0)
			paddedInput[5] = 0x80;
		if((threadIdx.x & 3) == 3)
		{
			paddedInput[4] = cuda_swab32(startNounce + thread);
			paddedInput[7] = 0x01000000;
		}

        uint32_t msgBitsliced[8];
        myr_to_bitslice_quad(paddedInput, msgBitsliced);

        uint32_t state[8];

        groestl512_progressMessage_quad(state, msgBitsliced);

        uint32_t out_state[16];
        from_bitslice_quad(state, out_state);

        if ((threadIdx.x & 0x03) == 0)
        {
			uint4 *outpHash = (uint4*)&hashBuffer[16 * thread];
			uint4 *phash = (uint4*)out_state;
			uint4 *outpt = outpHash;
			outpt[0] = phash[0];
			outpt[1] = phash[1];
			outpt[2] = phash[2];
			outpt[3] = phash[3];
		}
    }
}

__global__ void __launch_bounds__(512, 1)
 myriadgroestl_gpu_hash_quad2(uint32_t threads, uint32_t startNounce, uint32_t *const __restrict__ resNounce, const uint32_t *const __restrict__ hashBuffer)
{
    const uint32_t thread = (blockDim.x * blockIdx.x + threadIdx.x);
    if (thread < threads)
    {
        uint32_t out_state[16];
        const uint32_t *inpHash = &hashBuffer[16 * thread];
#pragma unroll 16
        for (int i=0; i < 16; i++)
            out_state[i] = inpHash[i];

        myriadgroestl_gpu_sha256(out_state);
        
        if (out_state[7] <= pTarget[7])
		{
			uint32_t tmp = atomicExch(resNounce, startNounce + thread);
			if (tmp != 0xffffffff)
				resNounce[1] = tmp;
		 }
    }
}

static THREAD cudaStream_t stream[3];
// Setup-Funktionen
__host__ void myriadgroestl_cpu_init(int thr_id, uint32_t threads)
{
	CUDA_SAFE_CALL(cudaSetDevice(device_map[thr_id]));
	CUDA_SAFE_CALL(cudaDeviceReset());
	CUDA_SAFE_CALL(cudaSetDeviceFlags(cudaschedule));
	CUDA_SAFE_CALL(cudaDeviceSetCacheConfig(cudaFuncCachePreferL1));
	CUDA_SAFE_CALL(cudaStreamCreate(&stream[0]));
	CUDA_SAFE_CALL(cudaStreamCreate(&stream[1]));
	CUDA_SAFE_CALL(cudaStreamCreate(&stream[2]));
	cudaMalloc(&d_resultNonce[thr_id], 4 * sizeof(uint32_t));

    // Speicher für temporäreHashes
	CUDA_SAFE_CALL(cudaMalloc(&d_outputHashes[thr_id], 16ULL * sizeof(uint32_t)*threads));
}

__host__ void myriadgroestl_cpu_setBlock(int thr_id, void *data, void *pTargetIn)
{
	cudaMemcpyToSymbolAsync(myriadgroestl_gpu_msg, data, 80, 0, cudaMemcpyHostToDevice, stream[0]);

	cudaMemsetAsync(d_resultNonce[thr_id], 0xFF, 4 * sizeof(uint32_t), stream[1]);
	cudaMemcpyToSymbolAsync(pTarget, pTargetIn, sizeof(uint32_t) * 8, 0, cudaMemcpyHostToDevice, stream[2]);
}

__host__ void myriadgroestl_cpu_hash(int thr_id, uint32_t threads, uint32_t startNounce, uint32_t *nounce)
{
    const uint32_t threadsperblock = 512;
	const uint32_t threadsperblock2 = 512;
    // Compute 3.0 benutzt die registeroptimierte Quad Variante mit Warp Shuffle
    // mit den Quad Funktionen brauchen wir jetzt 4 threads pro Hash, daher Faktor 4 bei der Blockzahl
    const int factor=4;

    // berechne wie viele Thread Blocks wir brauchen
    dim3 grid(factor*((threads + threadsperblock-1)/threadsperblock));
    dim3 block(threadsperblock);

	CUDA_SAFE_CALL(cudaDeviceSynchronize());
    myriadgroestl_gpu_hash_quad<<<grid, block>>>(threads, startNounce, d_outputHashes[thr_id]);
    dim3 grid2((threads + threadsperblock2-1)/threadsperblock2);
    myriadgroestl_gpu_hash_quad2<<<grid2, block>>>(threads, startNounce, d_resultNonce[thr_id], d_outputHashes[thr_id]);


    CUDA_SAFE_CALL(cudaMemcpy(nounce, d_resultNonce[thr_id], 4*sizeof(uint32_t), cudaMemcpyDeviceToHost));
}
