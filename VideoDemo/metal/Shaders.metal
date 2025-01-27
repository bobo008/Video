#include <metal_stdlib>
using namespace metal;

// 顶点数据结构
struct Vertex {
    float3 position [[attribute(0)]]; // 位置属性（Attribute 0）
    float4 color    [[attribute(1)]]; // 颜色属性（Attribute 1）
};

// 顶点着色器输出结构
struct VertexOut {
    float4 position [[position]]; // 裁剪空间坐标
    float4 color;                 // 颜色
};

// 统一缓冲区（MVP 矩阵）
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
};

// 顶点着色器
vertex VertexOut vertexShader(
                              const Vertex in [[stage_in]],      // 顶点输入
                              constant Uniforms &uniforms [[buffer(1)]] // 统一缓冲区
                              ) {
                                  VertexOut out;
                                  
                                  // 计算裁剪空间坐标
                                  out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
                                  
                                  // 直接传递颜色
                                  out.color = in.color;
                                  
                                  return out;
                              }

// 片段着色器
fragment float4 fragmentShader(
                               VertexOut in [[stage_in]] // 顶点着色器输出
                               ) {
                                   // 直接返回顶点颜色
                                   return in.color;
                               }
