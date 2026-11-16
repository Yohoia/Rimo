#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CFPlugInCOM.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
 assert(argc == 2);
 CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL,(const UInt8 *)argv[1],strlen(argv[1]),true);
 CFPlugInRef plugin = CFPlugInCreate(NULL,url); assert(plugin);
 CFArrayRef factories=CFPlugInFindFactoriesForPlugInTypeInPlugIn(kAudioServerPlugInTypeUUID,plugin); assert(factories && CFArrayGetCount(factories)==1);
 AudioServerPlugInDriverRef d=CFPlugInInstanceCreate(NULL,CFArrayGetValueAtIndex(factories,0),kAudioServerPlugInTypeUUID); assert(d);
 AudioServerPlugInHostInterface host = {0};
 assert((*d)->Initialize(d,&host)==noErr);
 AudioObjectPropertyAddress a={kAudioPlugInPropertyDeviceList,kAudioObjectPropertyScopeGlobal,0};
 UInt32 size=sizeof(AudioObjectID),actual=0;AudioObjectID device=0;
 assert((*d)->GetPropertyData(d,1,0,&a,0,NULL,size,&actual,&device)==noErr && device==2);
 a.mSelector=kAudioDevicePropertyDeviceUID;CFStringRef uid=NULL;size=sizeof(uid);
 assert((*d)->GetPropertyData(d,device,0,&a,0,NULL,size,&actual,&uid)==noErr);
 assert(CFEqual(uid,CFSTR("cn.yohoia.sofo.microphone")));CFRelease(uid);
 CFRelease(factories);CFRelease(plugin);CFRelease(url);
 puts("PASS: signed driver bundle loaded through CFPlugIn; factory; device list; microphone UID");
}
