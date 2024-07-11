// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef _V2DCONV__SYMS_H_
#define _V2DCONV__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODULE CLASSES
#include "V2dConv.h"

// SYMS CLASS
class V2dConv__Syms : public VerilatedSyms {
  public:
    
    // LOCAL STATE
    const char* __Vm_namep;
    bool __Vm_didInit;
    
    // SUBCELL STATE
    V2dConv*                       TOPp;
    
    // CREATORS
    V2dConv__Syms(V2dConv* topp, const char* namep);
    ~V2dConv__Syms() {}
    
    // METHODS
    inline const char* name() { return __Vm_namep; }
    
} VL_ATTR_ALIGNED(VL_CACHE_LINE_BYTES);

#endif  // guard
