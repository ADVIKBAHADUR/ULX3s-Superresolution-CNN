// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Primary design header
//
// This header should be included by all source files instantiating the design.
// The class here is then constructed to instantiate the design.
// See the Verilator manual for examples.

#ifndef _V2DCONV_H_
#define _V2DCONV_H_  // guard

#include "verilated.h"

//==========

class V2dConv__Syms;

//----------

VL_MODULE(V2dConv) {
  public:
    
    // PORTS
    // The application code writes and reads these signals to
    // propagate new values into/out from the Verilated model.
    VL_IN8(clk,0,0);
    VL_IN8(rst_n,0,0);
    VL_IN8(input_data[3][3][3],7,0);
    VL_OUT16(output_data[3][3][3],15,0);
    
    // LOCAL SIGNALS
    // Internals; generally not touched by application code
    CData/*3:0*/ Conv2D__DOT__state;
    CData/*5:0*/ Conv2D__DOT__kernel;
    CData/*2:0*/ Conv2D__DOT__conv;
    CData/*2:0*/ Conv2D__DOT__depth;
    CData/*2:0*/ Conv2D__DOT__i;
    CData/*2:0*/ Conv2D__DOT__j;
    CData/*1:0*/ Conv2D__DOT__ki;
    CData/*1:0*/ Conv2D__DOT__kj;
    QData/*47:0*/ Conv2D__DOT__sum;
    IData/*31:0*/ Conv2D__DOT__Weights[5][64][64][3][3];
    IData/*31:0*/ Conv2D__DOT__Biases[5][64];
    
    // LOCAL VARIABLES
    // Internals; generally not touched by application code
    CData/*0:0*/ __Vclklast__TOP__clk;
    CData/*0:0*/ __Vclklast__TOP__rst_n;
    SData/*15:0*/ Conv2D__DOT____Vlvbound1;
    IData/*31:0*/ Conv2D__DOT____Vcellout__SuperResolution__conv_biases[5][64];
    IData/*31:0*/ Conv2D__DOT____Vcellout__SuperResolution__conv_weights[5][64][64][3][3];
    
    // INTERNAL VARIABLES
    // Internals; generally not touched by application code
    V2dConv__Syms* __VlSymsp;  // Symbol table
    
    // CONSTRUCTORS
  private:
    VL_UNCOPYABLE(V2dConv);  ///< Copying not allowed
  public:
    /// Construct the model; called by application code
    /// The special name  may be used to make a wrapper with a
    /// single model invisible with respect to DPI scope names.
    V2dConv(const char* name = "TOP");
    /// Destroy the model; called (often implicitly) by application code
    ~V2dConv();
    
    // API METHODS
    /// Evaluate the model.  Application must call when inputs change.
    void eval();
    /// Simulation complete, run final blocks.  Application must call on completion.
    void final();
    
    // INTERNAL METHODS
  private:
    static void _eval_initial_loop(V2dConv__Syms* __restrict vlSymsp);
  public:
    void __Vconfigure(V2dConv__Syms* symsp, bool first);
  private:
    static QData _change_request(V2dConv__Syms* __restrict vlSymsp);
    void _ctor_var_reset() VL_ATTR_COLD;
  public:
    static void _eval(V2dConv__Syms* __restrict vlSymsp);
  private:
#ifdef VL_DEBUG
    void _eval_debug_assertions();
#endif  // VL_DEBUG
  public:
    static void _eval_initial(V2dConv__Syms* __restrict vlSymsp) VL_ATTR_COLD;
    static void _eval_settle(V2dConv__Syms* __restrict vlSymsp) VL_ATTR_COLD;
    static void _initial__TOP__1(V2dConv__Syms* __restrict vlSymsp) VL_ATTR_COLD;
    static void _sequent__TOP__2(V2dConv__Syms* __restrict vlSymsp);
    static void _settle__TOP__3(V2dConv__Syms* __restrict vlSymsp) VL_ATTR_COLD;
} VL_ATTR_ALIGNED(VL_CACHE_LINE_BYTES);

//----------


#endif  // guard
