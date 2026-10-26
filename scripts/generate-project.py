from pathlib import Path
import hashlib

def ident(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
objects=[]
def obj(key, body):
 i=ident(key);objects.append(f'{i} = {{ {body} }};');return i
shared=sorted(Path('Shared').glob('*.swift'))
shares=sorted(Path('ShareExtension').glob('*.swift'))+shared
sources=sorted(Path('CatNotes').rglob('*.swift'))+shared
tests=sorted(Path('CatNotesTests').glob('*.swift'))
uitests=sorted(Path('CatNotesUITests').glob('*.swift'))
refs={}
for p in dict.fromkeys(sources+tests+uitests+shares):
 refs[str(p)]=obj(str(p),f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{p}"; sourceTree = SOURCE_ROOT;')
app=obj('app','isa = PBXFileReference; explicitFileType = wrapper.application; path = CatNotes.app; sourceTree = BUILT_PRODUCTS_DIR;')
test=obj('test','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CatNotesTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
uitest=obj('uitest','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = CatNotesUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; name = Products; children = ({app}, {test}, {uitest}); sourceTree = "<group>";')
root=obj('root','isa = PBXGroup; children = ('+', '.join(refs.values())+f', {products}); sourceTree = "<group>";')
def configs(key,extra):
 ids=[]
 for name in ['Debug','Release']:
  flags='SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES;' if name=='Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
  ids.append(obj(key+name,f'isa = XCBuildConfiguration; name = {name}; buildSettings = {{ {extra} {flags} }};'))
 return obj(key+'configs','isa = XCConfigurationList; buildConfigurations = ('+', '.join(ids)+'); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
common='IPHONEOS_DEPLOYMENT_TARGET = 16.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;'
projectconfig=configs('project',common)
appconfig=configs('app', 'CODE_SIGN_ENTITLEMENTS = Config/App.entitlements; INFOPLIST_FILE = Config/AppInfo.plist; PRODUCT_BUNDLE_IDENTIFIER = fr.catnotes.app; PRODUCT_NAME = CatNotes; TARGETED_DEVICE_FAMILY = "1,2"; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = CatNotes; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES; INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"; INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 8; CODE_SIGN_STYLE = Automatic;')
testconfig=configs('test','PRODUCT_BUNDLE_IDENTIFIER = fr.catnotes.tests; PRODUCT_NAME = CatNotesTests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CatNotes.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/CatNotes"; BUNDLE_LOADER = "$(TEST_HOST)"; TARGETED_DEVICE_FAMILY = "1,2";')
uitestconfig=configs('uitest','PRODUCT_BUNDLE_IDENTIFIER = fr.catnotes.uitests; PRODUCT_NAME = CatNotesUITests; GENERATE_INFOPLIST_FILE = YES; TEST_TARGET_NAME = CatNotes; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic;')
def phase(key,files):
 builds=[obj(key+'build'+str(p),f'isa = PBXBuildFile; fileRef = {refs[str(p)]};') for p in files]
 return obj(key,f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ('+', '.join(builds)+'); runOnlyForDeploymentPostprocessing = 0;')
appsource=phase('appsources',sources);testsource=phase('testsources',tests)
uitestsource=phase('uitestsources',uitests)
resources=obj('resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
# Include configuration only when explicitly created by the developer.
config=Path('Config/Supabase.plist')
if config.exists():
 ref=obj('supabaseconfig','isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Config/Supabase.plist; sourceTree = SOURCE_ROOT;')
 build=obj('supabaseconfigbuild',f'isa = PBXBuildFile; fileRef = {ref};')
 objects=[s.replace('files = (); runOnlyForDeploymentPostprocessing',f'files = ({build}); runOnlyForDeploymentPostprocessing') if s.startswith(resources) else s for s in objects]
shareconfig=configs('share', 'PRODUCT_BUNDLE_IDENTIFIER = fr.catnotes.app.share; PRODUCT_NAME = CatNotesShare; MARKETING_VERSION = 0.1.0; CURRENT_PROJECT_VERSION = 8; INFOPLIST_FILE = Config/ShareInfo.plist; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_ENTITLEMENTS = Config/Share.entitlements; TARGETED_DEVICE_FAMILY = "1,2"; APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES; CODE_SIGN_STYLE = Automatic;')
shareproduct=obj('shareproduct','isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; path = CatNotesShare.appex; sourceTree = BUILT_PRODUCTS_DIR;')
sharesource=phase('sharesources',shares)
sharetarget=obj('sharetarget',f'isa = PBXNativeTarget; buildConfigurationList = {shareconfig}; buildPhases = ({sharesource}); buildRules = (); dependencies = (); name = CatNotesShare; productName = CatNotesShare; productReference = {shareproduct}; productType = "com.apple.product-type.app-extension";')
shareproxy=obj('shareproxy',f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {sharetarget}; remoteInfo = CatNotesShare;')
sharedep=obj('sharedep',f'isa = PBXTargetDependency; target = {sharetarget}; targetProxy = {shareproxy};')
sharebuild=obj('sharebuild',f'isa = PBXBuildFile; fileRef = {shareproduct}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy); }};')
embed=obj('embed',f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({sharebuild}); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
apptarget=obj('apptarget' ,f'isa = PBXNativeTarget; buildConfigurationList = {appconfig}; buildPhases = ({appsource}, {resources}, {embed}); buildRules = (); dependencies = ({sharedep}); name = CatNotes; productName = CatNotes; productReference = {app}; productType = "com.apple.product-type.application";')
proxy=obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {apptarget}; remoteInfo = CatNotes;')
dep=obj('dep',f'isa = PBXTargetDependency; target = {apptarget}; targetProxy = {proxy};')
testtarget=obj('testtarget',f'isa = PBXNativeTarget; buildConfigurationList = {testconfig}; buildPhases = ({testsource}); buildRules = (); dependencies = ({dep}); name = CatNotesTests; productName = CatNotesTests; productReference = {test}; productType = "com.apple.product-type.bundle.unit-test";')
uitestdep=obj('uitestdep',f'isa = PBXTargetDependency; target = {apptarget}; targetProxy = {proxy};')
uitesttarget=obj('uitesttarget',f'isa = PBXNativeTarget; buildConfigurationList = {uitestconfig}; buildPhases = ({uitestsource}); buildRules = (); dependencies = ({uitestdep}); name = CatNotesUITests; productName = CatNotesUITests; productReference = {uitest}; productType = "com.apple.product-type.bundle.ui-testing";')
project=obj('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {uitesttarget} = {{ TestTargetID = {apptarget}; }}; }}; }}; buildConfigurationList = {projectconfig}; compatibilityVersion = "Xcode 14.0"; developmentRegion = fr; knownRegions = (fr,en); mainGroup = {root}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({apptarget}, {testtarget}, {uitesttarget}, {sharetarget});')
p=Path('CatNotes.xcodeproj');p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}')
scheme=p/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'CatNotes.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{apptarget}" BuildableName="CatNotes.app" BlueprintName="CatNotes" ReferencedContainer="container:CatNotes.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{testtarget}" BuildableName="CatNotesTests.xctest" BlueprintName="CatNotesTests" ReferencedContainer="container:CatNotes.xcodeproj"/></TestableReference><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitesttarget}" BuildableName="CatNotesUITests.xctest" BlueprintName="CatNotesUITests" ReferencedContainer="container:CatNotes.xcodeproj"/></TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{apptarget}" BuildableName="CatNotes.app" BlueprintName="CatNotes" ReferencedContainer="container:CatNotes.xcodeproj"/></BuildableProductRunnable></LaunchAction></Scheme>''')
