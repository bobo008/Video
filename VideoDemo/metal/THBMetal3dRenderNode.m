#import "THBMetal3dRenderNode.h"
#import "AAPLMathUtilities.h"
#import <Metal/Metal.h>

typedef struct {
    vector_float3 position;
    vector_float4 color;
} Vertex;

typedef struct {
    matrix_float4x4 modelViewProjectionMatrix;
} Uniforms;

@interface THBMetal3dRenderNode()
@property (nonatomic) id<MTLDevice> device;

// 新增深度纹理属性
@property (nonatomic) id<MTLTexture> dstTexture;
@property (nonatomic) id<MTLTexture> depthTexture;

@property (nonatomic) id<MTLRenderPipelineState> renderToTextureRenderPipeline;
@property (nonatomic) id<MTLDepthStencilState> depthStencilState; // 深度测试状态
@property (nonatomic) id<MTLCommandQueue> commandQueue;

@property (nonatomic) MTLRenderPassDescriptor *renderToTextureRenderPassDescriptor;
@end

@implementation THBMetal3dRenderNode

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setup];
    }
    return self;
}


- (void)setup {
    self.device = MTLCreateSystemDefaultDevice();
    
    // 创建颜色纹理
    MTLTextureDescriptor *texDescriptor = [MTLTextureDescriptor new];
    texDescriptor.textureType = MTLTextureType2D;
    texDescriptor.width = 1000;
    texDescriptor.height = 1000;
    texDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
    texDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    self.dstTexture = [self.device newTextureWithDescriptor:texDescriptor];
    
    // 创建深度纹理（新增）
    MTLTextureDescriptor *depthDescriptor = [MTLTextureDescriptor new];
    depthDescriptor.textureType = MTLTextureType2D;
    depthDescriptor.width = 1000;
    depthDescriptor.height = 1000;
    depthDescriptor.pixelFormat = MTLPixelFormatDepth32Float;
    depthDescriptor.usage = MTLTextureUsageRenderTarget;
    depthDescriptor.storageMode = MTLStorageModePrivate;
    self.depthTexture = [self.device newTextureWithDescriptor:depthDescriptor];
    
    // 配置渲染通道（添加深度附件）
    MTLRenderPassDescriptor *renderPassDescriptor = [MTLRenderPassDescriptor new];
    renderPassDescriptor.colorAttachments[0].texture = self.dstTexture;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    // 配置深度附件（新增）
    renderPassDescriptor.depthAttachment.texture = self.depthTexture;
    renderPassDescriptor.depthAttachment.loadAction = MTLLoadActionClear;
    renderPassDescriptor.depthAttachment.clearDepth = 1.0;
    renderPassDescriptor.depthAttachment.storeAction = MTLStoreActionDontCare;
    
    self.renderToTextureRenderPassDescriptor = renderPassDescriptor;
    
    // 创建深度模板状态（新增）
    MTLDepthStencilDescriptor *depthStencilDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStencilDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStencilDesc.depthWriteEnabled = YES;
    self.depthStencilState = [self.device newDepthStencilStateWithDescriptor:depthStencilDesc];
    
    // 创建渲染管线（添加深度格式）
    MTLVertexDescriptor *vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
    vertexDescriptor.attributes[0].format = MTLVertexFormatFloat3;
    vertexDescriptor.attributes[0].offset = 0;
    vertexDescriptor.attributes[0].bufferIndex = 0;
    vertexDescriptor.attributes[1].format = MTLVertexFormatFloat4;
    vertexDescriptor.attributes[1].offset = sizeof(float) * 4;
    vertexDescriptor.attributes[1].bufferIndex = 0;
    vertexDescriptor.layouts[0].stride = sizeof(Vertex);
    
    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    MTLRenderPipelineDescriptor *pipelineDesc = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDesc.vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
    pipelineDesc.fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];
    pipelineDesc.colorAttachments[0].pixelFormat = self.dstTexture.pixelFormat;
    pipelineDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float; // 深度格式
    pipelineDesc.vertexDescriptor = vertexDescriptor;
    
    NSError *error;
    self.renderToTextureRenderPipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
    
    self.commandQueue = [self.device newCommandQueue];
}




- (UIImage *)render {
    // 透视矩阵参数
    float aspect = 1;
    float fov = (float)M_PI / 4.0f; // 45度
    float near = 0.1f;
    float far = 100.0f;
    
    matrix_float4x4 projectionMatrix = matrix_perspective_right_hand(fov, aspect, near, far);
    

    vector_float3 eyePos = {-2.f, 2.f, 2.f};
    vector_float3 eyeTarget = {0.f, 0.f, 0.f};
    vector_float3 eyeUp = {1.f, 1.f, -1.f};
    matrix_float4x4 viewMatrix = matrix_look_at_right_hand(eyePos, eyeTarget, eyeUp);
    
    
    // 模型矩阵 (旋转立方体)
    static float angle = 0;
    //    angle += 0.01f;
    matrix_float4x4 modelMatrix = matrix4x4_rotation(angle, (vector_float3){1, 1, 0});
    
    
    // MVP矩阵组合
    matrix_float4x4 modelViewProjectionMatrix = matrix_multiply(
                                                                projectionMatrix,
                                                                matrix_multiply(viewMatrix, modelMatrix)
                                                                );
    
    
    
    //    RGBA
    // 4. 创建顶点数据 (立方体)
    static const Vertex vertices[] = {
        // 前面 (Z+)
        {{-0.5, -0.5,  0.5}, {1, 0, 0, 1}},
        {{ 0.5, -0.5,  0.5}, {0, 1, 0, 1}},
        {{-0.5,  0.5,  0.5}, {0, 0, 1, 1}},
        {{ 0.5,  0.5,  0.5}, {1, 0, 0, 1}},
        
        // 后面 (Z-)
        {{-0.5, -0.5, -0.5}, {1, 0, 1, 1}},
        {{ 0.5, -0.5, -0.5}, {0, 1, 1, 1}},
        {{-0.5,  0.5, -0.5}, {1, 1, 1, 1}},
        {{ 0.5,  0.5, -0.5}, {0, 0, 1, 1}},
    };
    
    id <MTLBuffer> vertexBuffer = [self.device newBufferWithBytes:vertices
                                                           length:sizeof(vertices)
                                                          options:MTLResourceStorageModeShared];
    
    // 5. 创建索引缓冲
    static const uint16_t indices[] = {
        // 前面
        0, 1, 2, 2, 1, 3,
        // 右面
        1, 5, 3, 3, 5, 7,
        // 后面
        5, 4, 7, 7, 4, 6,
        // 左面
        4, 0, 6, 6, 0, 2,
        // 顶面
        2, 3, 6, 6, 3, 7,
        // 底面
        4, 5, 0, 0, 5, 1
    };
    
    id <MTLBuffer> indexBuffer = [self.device newBufferWithBytes:indices
                                                          length:sizeof(indices)
                                                         options:MTLResourceStorageModeShared];
    
    // 6. 创建统一缓冲区
    id <MTLBuffer> uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms)
                                                            options:MTLResourceStorageModeShared];
    
    memcpy(uniformBuffer.contents, &modelViewProjectionMatrix, sizeof(Uniforms));
    
    
    // 1. 准备渲染命令
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    
    
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:self.renderToTextureRenderPassDescriptor];
    renderEncoder.label = @"Offscreen Render Pass";
    
    [renderEncoder setDepthStencilState:self.depthStencilState];
    [renderEncoder setRenderPipelineState:self.renderToTextureRenderPipeline];
    
    
    [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [renderEncoder setVertexBuffer:uniformBuffer offset:0 atIndex:1];
    
    [renderEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:[indexBuffer length]/sizeof(uint16_t)
                               indexType:MTLIndexTypeUInt16
                             indexBuffer:indexBuffer
                       indexBufferOffset:0];
    
    [renderEncoder endEncoding];
    
    [commandBuffer commit];
    
    [commandBuffer waitUntilCompleted];
    
    
    CVPixelBufferRef ret = [self convertMTLTextureToCVPixelBuffer:self.dstTexture];
    
    return [self imageForPixelBuffer:ret];
}






- (UIImage *)imageForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CGImageRef cgImage = [self cgImageForPixelBuffer:pixelBuffer];
    UIImage *image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    return image;
}


- (CGImageRef)cgImageForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    assert(kCVPixelFormatType_32BGRA == CVPixelBufferGetPixelFormatType(pixelBuffer));
    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    const size_t SIZE = height * bytesPerRow * sizeof(Byte);
    void *data = malloc(SIZE);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    uint32_t bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGImageByteOrder32Little;
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    memcpy(data, baseAddress, SIZE);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(data);
    return cgImage;
}



- (CVPixelBufferRef)convertMTLTextureToCVPixelBuffer:(id<MTLTexture>)texture {
    // 1. 检查纹理格式
    if (texture.pixelFormat != MTLPixelFormatBGRA8Unorm) {
        NSLog(@"不支持的纹理格式: %lu", (unsigned long)texture.pixelFormat);
        return NULL;
    }
    
    // 2. 创建 CVPixelBuffer
    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *pixelBufferAttributes = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferMetalCompatibilityKey: @(YES) // 允许 Metal 访问
    };
    
    CVReturn status = CVPixelBufferCreate(
                                          kCFAllocatorDefault,
                                          texture.width,
                                          texture.height,
                                          kCVPixelFormatType_32BGRA, // 与 Metal 的 BGRA8Unorm 格式匹配
                                          (__bridge CFDictionaryRef)pixelBufferAttributes,
                                          &pixelBuffer
                                          );
    
    if (status != kCVReturnSuccess || !pixelBuffer) {
        NSLog(@"创建 CVPixelBuffer 失败: %d", status);
        return NULL;
    }
    
    // 3. 锁定 CVPixelBuffer 基地址
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    
    // 4. 从 Metal 纹理复制数据到 CVPixelBuffer
    [texture getBytes:baseAddress
          bytesPerRow:bytesPerRow
           fromRegion:MTLRegionMake2D(0, 0, texture.width, texture.height)
          mipmapLevel:0];
    
    // 5. 解锁并返回
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}


@end


