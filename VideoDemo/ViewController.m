//
//  ViewController.m
//  VideoDemo
//
//  Created by tanghongbo on 2025/1/24.
//

#import "ViewController.h"
#import "THBMetal3dRenderNode.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIImage *image = [[[THBMetal3dRenderNode alloc] init] render];
    
    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 200, 393, 393)];
    imageView.image = image;
    [self.view addSubview:imageView];
    return;
    
    
    
    // Do any additional setup after loading the view.
}


@end
