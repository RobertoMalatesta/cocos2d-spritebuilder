//
//  CCEffectDFInnerGlow.m
//  cocos2d-ios
//
//  Created by Oleg Osin on 9/11/14.
//
//

#import "CCEffectDFInnerGlow.h"

#if CC_EFFECTS_EXPERIMENTAL

#import "CCEffectShader.h"
#import "CCEffectShaderBuilderGL.h"
#import "CCEffect_Private.h"
#import "CCColor.h"
#import "CCRenderer.h"
#import "CCTexture.h"


@interface CCEffectDFInnerGlow ()
@property (nonatomic, assign) float innerMin;
@property (nonatomic, assign) float innerMax;
@end


@interface CCEffectDFInnerGlowImplGL : CCEffectImpl
@property (nonatomic, weak) CCEffectDFInnerGlow *interface;
@end


@implementation CCEffectDFInnerGlowImplGL {
    float _innerMin;
    float _innerMax;
}

-(id)initWithInterface:(CCEffectDFInnerGlow *)interface
{
    NSArray *renderPasses = [CCEffectDFInnerGlowImplGL buildRenderPassesWithInterface:interface];
    NSArray *shaders = [CCEffectDFInnerGlowImplGL buildShaders];
    
    if((self = [super initWithRenderPasses:renderPasses shaders:shaders]))
    {
        self.interface = interface;
        self.debugName = @"CCEffectDFInnerGlowImplGL";
    }
    return self;
}

+ (NSArray *)buildShaders
{
    return @[[[CCEffectShader alloc] initWithVertexShaderBuilder:[CCEffectShaderBuilderGL defaultVertexShaderBuilder] fragmentShaderBuilder:[CCEffectDFInnerGlowImplGL fragShaderBuilder]]];
}

+ (CCEffectShaderBuilder *)fragShaderBuilder
{
    NSArray *functions = [CCEffectDFInnerGlowImplGL buildFragmentFunctions];
    NSArray *temporaries = @[[CCEffectFunctionTemporary temporaryWithType:@"vec4" name:@"tmp" initializer:CCEffectInitPreviousPass]];
    NSArray *calls = @[[[CCEffectFunctionCall alloc] initWithFunction:functions[0] outputName:@"innerGlow" inputs:nil]];
    
    NSArray *uniforms = @[
                          [CCEffectUniform uniform:@"sampler2D" name:CCShaderUniformPreviousPassTexture value:(NSValue *)[CCTexture none]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Center value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec2" name:CCShaderUniformTexCoord1Extents value:[NSValue valueWithGLKVector2:GLKVector2Make(0.0f, 0.0f)]],
                          [CCEffectUniform uniform:@"vec4" name:@"u_fillColor" value:[NSValue valueWithGLKVector4:[CCColor blackColor].glkVector4]],
                          [CCEffectUniform uniform:@"vec4" name:@"u_glowColor" value:[NSValue valueWithGLKVector4:[CCColor blackColor].glkVector4]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_glowInnerWidth" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.5, 1.0)]],
                          [CCEffectUniform uniform:@"vec2" name:@"u_glowOuterWidth" value:[NSValue valueWithGLKVector2:GLKVector2Make(0.47, 0.5)]]
                          ];
    
    return [[CCEffectShaderBuilderGL alloc] initWithType:CCEffectShaderBuilderFragment
                                               functions:functions
                                                   calls:calls
                                             temporaries:temporaries
                                                uniforms:uniforms
                                                varyings:@[]];
}

+(NSArray *)buildFragmentFunctions
{
    NSString* effectPrefix =
        @"#ifdef GL_ES\n"
        @"#ifdef GL_OES_standard_derivatives\n"
        @"#extension GL_OES_standard_derivatives : enable\n"
        @"#endif\n"
        @"#endif\n";

    NSString* effectBody = CC_GLSL(
                                   vec4 outputColor = u_fillColor;
                                   if(u_fillColor.a == 0.0)
                                       outputColor = texture2D(cc_MainTexture, cc_FragTexCoord1);
                                   
                                   float distAlphaMask = texture2D(cc_NormalMapTexture, cc_FragTexCoord1).r;
                                   
                                   float min = u_glowInnerWidth.x;
                                   float max = u_glowInnerWidth.y;

                                   if(min == 0.5 && max == 0.5)
                                   {
                                       float center = 0.5;
                                       float transition = fwidth(distAlphaMask) * 1.0;
                                       
                                       min = center - transition;
                                       max = center + transition;
                                       
                                       // soft edges
                                       outputColor.a *= smoothstep(min, max, distAlphaMask);
                                       
                                       vec4 glowc = u_fillColor * smoothstep(min, max, transition);
                                       outputColor = mix(glowc, outputColor, outputColor.a);

                                       return outputColor;
                                   }
                                   
                                   // 0.5 == center(edge),  < 0.5 == outside, > 0.5 == inside
                                   float min0 = u_glowOuterWidth.x;
                                   float max0 = u_glowOuterWidth.y;
                                   float min1 = u_glowInnerWidth.x;
                                   float max1 = u_glowInnerWidth.y;
                                   if(distAlphaMask >= min0 && distAlphaMask <= max1) // apply glow
                                   {
                                       float oFactor = 1.0;
                                       if(distAlphaMask <= min1)
                                       {
                                           oFactor = smoothstep(min0, min1, distAlphaMask);
                                       }
                                       else
                                       {
                                           oFactor = smoothstep(max1, max0, distAlphaMask);
                                       }
                                       
                                       outputColor = mix(outputColor, u_glowColor, oFactor);
                                   }
                                   
                                   float center = 0.5;
                                   float transition = fwidth(distAlphaMask) * 1.0;
                                   
                                   min = center - transition;
                                   max = center + transition;
                                   
                                   // soft edges
                                   outputColor.a *= smoothstep(min, max, distAlphaMask);
                                   
                                   vec4 glowc = u_fillColor * smoothstep(min, max, transition);
                                   outputColor = mix(glowc, outputColor, outputColor.a);
                                   
                                   return outputColor;
                                   
                                   );
    
    CCEffectFunction* fragmentFunction = [[CCEffectFunction alloc] initWithName:@"innerGlowFunc"
                                                                           body:[effectPrefix stringByAppendingString:effectBody] inputs:nil returnType:@"vec4"];
    return @[fragmentFunction];
}

+ (NSArray *)buildRenderPassesWithInterface:(CCEffectDFInnerGlow *)interface
{
    __weak CCEffectDFInnerGlow *weakInterface = interface;

    CCEffectRenderPass *pass0 = [[CCEffectRenderPass alloc] init];
    pass0.debugLabel = @"CCEffectDFInnerGlow pass 0";
    pass0.blendMode = [CCBlendMode premultipliedAlphaMode];
    pass0.beginBlocks = @[[[CCEffectRenderPassBeginBlockContext alloc] initWithBlock:^(CCEffectRenderPass *pass, CCEffectRenderPassInputs *passInputs){
        
        passInputs.shaderUniforms[CCShaderUniformNormalMapTexture] = weakInterface.distanceField;
        passInputs.shaderUniforms[CCShaderUniformMainTexture] = passInputs.previousPassTexture;
        passInputs.shaderUniforms[CCShaderUniformPreviousPassTexture] = passInputs.previousPassTexture;
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_fillColor"]] = [NSValue valueWithGLKVector4:weakInterface.fillColor.glkVector4];
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_glowColor"]] = [NSValue valueWithGLKVector4:weakInterface.glowColor.glkVector4];
        
        passInputs.shaderUniforms[passInputs.uniformTranslationTable[@"u_glowInnerWidth"]] = [NSValue valueWithGLKVector2:GLKVector2Make(weakInterface.innerMin, weakInterface.innerMax)];
        
    }]];
    
    return @[pass0];
}

@end


@implementation CCEffectDFInnerGlow
{
    float _fieldScaleFactor;
}

-(id)init
{
    return [self initWithGlowColor:[CCColor redColor] fillColor:[CCColor blackColor] glowWidth:3 fieldScale:32 distanceField:[CCTexture none]];
}

-(id)initWithGlowColor:(CCColor*)glowColor fillColor:(CCColor*)fillColor glowWidth:(int)glowWidth fieldScale:(float)fieldScale distanceField:(CCTexture*)distanceField
{
    if((self = [super init]))
    {        
        self.effectImpl = [[CCEffectDFInnerGlowImplGL alloc] initWithInterface:self];
        self.debugName = @"CCEffectDFInnerGlow";

        _fieldScaleFactor = fieldScale; // 32 4096/128 (input distance field size / output df size)
        _fillColor = fillColor;
        _glowColor = glowColor;
        _distanceField = distanceField;
        
        self.glowWidth = glowWidth;
    }
    return self;
}

+(instancetype)effectWithGlowColor:(CCColor*)glowColor fillColor:(CCColor*)fillColor glowWidth:(int)glowWidth fieldScale:(float)fieldScale distanceField:(CCTexture*)distanceField
{
    return [[self alloc] initWithGlowColor:glowColor fillColor:fillColor glowWidth:glowWidth fieldScale:fieldScale distanceField:distanceField];
}

-(void)setGlowWidth:(int)glowWidth
{
    _glowWidth = glowWidth;
    float glowWidthNormalized = ((float)glowWidth)/255.0 * _fieldScaleFactor;

    // 0.5 == center(edge), < 0.5 == outside, > 0.5 == inside
    _innerMin = 0.5;
    _innerMax = _innerMin + glowWidthNormalized;
}


@end

#endif
