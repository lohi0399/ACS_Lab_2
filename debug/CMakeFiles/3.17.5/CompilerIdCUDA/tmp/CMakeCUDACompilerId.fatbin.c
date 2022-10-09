#ifndef __SKIP_INTERNAL_FATBINARY_HEADERS
#include "fatbinary_section.h"
#endif
#define __CUDAFATBINSECTION  ".nvFatBinSegment"
#define __CUDAFATBINDATASECTION  ".nv_fatbin"
asm(
".section .nv_fatbin, \"a\"\n"
".align 8\n"
"fatbinData:\n"
".quad 0x00100001ba55ed50,0x0000000000000080,0x0000004801010001,0x0000000000000038\n"
".quad 0x0000004000000036,0x0000003200070006,0x0000000000000000,0x0000000000002011\n"
".quad 0x0000000000000000,0x0000000000000038,0x0000000000000000,0x762e21f000010a13\n"
".quad 0x37206e6f69737265,0x677261742e0a362e,0x30355f6d73207465,0x7365726464612e0a\n"
".quad 0x3620657a69735f73, 0x0000000a0a0a0a34\n"
".text\n");
#ifdef __cplusplus
extern "C" {
#endif
extern const unsigned long long fatbinData[18];
#ifdef __cplusplus
}
#endif
#ifdef __cplusplus
extern "C" {
#endif
static const __fatBinC_Wrapper_t __fatDeviceText __attribute__ ((aligned (8))) __attribute__ ((section (__CUDAFATBINSECTION)))= 
	{ 0x466243b1, 1, fatbinData, 0 };
#ifdef __cplusplus
}
#endif
