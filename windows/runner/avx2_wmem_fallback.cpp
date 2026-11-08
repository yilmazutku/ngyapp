#if defined(_M_X64) && !defined(_M_ARM64EC)
extern "C" __declspec(selectany) int _Avx2WmemEnabledWeakValue = 0;
#pragma comment(linker, "/alternatename:_Avx2WmemEnabled=_Avx2WmemEnabledWeakValue")
#endif
