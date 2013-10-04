//
//  GuideTaxonViewController.m
//  iNaturalist
//
//  Created by Ken-ichi Ueda on 9/16/13.
//  Copyright (c) 2013 iNaturalist. All rights reserved.
//

#import "GuideTaxonViewController.h"
#import "Observation.h"
#import "ObservationDetailViewController.h"
#import "RXMLElement+Helpers.h"
#import "PhotoSource.h"
#import "GuidePhotoViewController.h"
#import "GuideImageXML.h"

static const int WebViewTag = 1;

@implementation GuideTaxonViewController
@synthesize webView = _webView;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    // this is dumb, but the TTPhotoViewController forcibly sets the bar style, so we need to reset it
    self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
    [super viewWillAppear:animated];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (!self.webView) {
        self.webView = (UIWebView *)[self.view viewWithTag:WebViewTag];
    }
    self.webView.delegate = self;
    NSString *xmlString = [self.guideTaxon.xml xmlString];
    BOOL local = [[NSFileManager defaultManager] fileExistsAtPath:[self.guideTaxon.guide.dirPath stringByAppendingPathComponent:@"files"]];
    if (xmlString && [xmlString rangeOfString:@"xsl"].location == NSNotFound) {
        NSString *xslPath;
        if (local) {
            xslPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"guide_taxon-local.xsl"];
        } else {
            xslPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"guide_taxon-remote.xsl"];
        }
        NSString *header = [NSString stringWithFormat:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<?xml-stylesheet type=\"text/xsl\" href=\"%@\"?>\n<INatGuide xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:dcterms=\"http://purl.org/dc/terms/\" xmlns:eol=\"http://www.eol.org/transfer/content/1.0\">", xslPath];
        xmlString = [[header stringByAppendingString:xmlString] stringByAppendingString:@"</INatGuide>"];
    }
    NSURL *baseURL = [NSURL fileURLWithPath:self.guideTaxon.guide.dirPath];
    [self.webView loadData:[xmlString dataUsingEncoding:NSUTF8StringEncoding]
                  MIMEType:@"text/xml"
          textEncodingName:@"utf-8"
                   baseURL:baseURL];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self.navigationController setToolbarHidden:YES animated:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidUnload {
    [self setWebView:nil];
    [super viewDidUnload];
}
- (IBAction)clickedObserve:(id)sender {
    [self performSegueWithIdentifier:@"GuideTaxonObserveSegue" sender:sender];
}
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GuideTaxonObserveSegue"]) {
        ObservationDetailViewController *vc = [segue destinationViewController];
        [vc setDelegate:self];
        Observation *o = [Observation object];
        o.localObservedOn = [NSDate date];
        o.speciesGuess = [[self.guideTaxon.xml atXPath:@"name"] text];
        [vc setObservation:o];
    }
}

# pragma mark - UIWebViewDelegate
// http://engineering.tumblr.com/post/32329287335/javascript-native-bridge-for-ioss-uiwebview
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSString *urlString = [[request URL] absoluteString];
    if ([urlString hasPrefix:@"js:"]) {
        NSString *jsonString = [[[urlString componentsSeparatedByString:@"js:"] lastObject]
                                stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        
        NSError *error;
        id parameters = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers
                                                          error:&error];
        if (error) {
            NSLog(@"error: %@", error);
        } else {
            // TODO: Logic based on parameters
        }
    } else if ([urlString hasPrefix:@"file:"] && [urlString rangeOfString:@"files/"].location != NSNotFound) {
        [self showAssetByURL:urlString];
    } else if (([urlString hasPrefix:@"http:"] || [urlString hasPrefix:@"https:"]) &&
               [self.guideTaxon.xml atXPath:[NSString stringWithFormat:@"descendant::*[text()='%@']", urlString]]) {
        [self showAssetByURL:urlString];
    } else if ([urlString hasPrefix:@"file:"]) {
        return YES;
    }
    return NO;
}

# pragma mark - GuideTaxonViewController
- (void)showAssetByURL:(NSString *)url
{
    NSString *name = [self.guideTaxon.xml atXPath:@"displayName"].text;
    if (!name) {
        name = [self.guideTaxon.xml atXPath:@"name"].text;
    }
    NSString *title = [NSString stringWithFormat:NSLocalizedString(@"Photos for %@", nil), name];
    PhotoSource *photoSource = [[PhotoSource alloc]
                                initWithPhotos:self.guideTaxon.guidePhotos
                                title:title];
    GuidePhotoViewController *vc = [[GuidePhotoViewController alloc] init];
    vc.photoSource = photoSource;
    vc.currentURL = url;
    [self.navigationController setToolbarHidden:YES];
    [self.navigationController pushViewController:vc animated:YES];
}

@end
