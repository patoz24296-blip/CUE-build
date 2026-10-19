"""Fail before distributing an IPA with the wrong layout or platform."""
import plistlib
import sys
import zipfile

def verify(path):
    with zipfile.ZipFile(path) as ipa:
        names = ipa.namelist()
        apps = {n.split('/')[1] for n in names if n.startswith('Payload/') and '.app/' in n}
        assert apps == {'CUE.app'}, f'Expected one app in Payload, got {apps}'
        root = 'Payload/CUE.app/'
        info = plistlib.loads(ipa.read(root + 'Info.plist'))
        assert info['CFBundlePackageType'] == 'APPL'
        assert info['CFBundleIdentifier'] == 'studio.cue.cue'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Simulator builds cannot be sideloaded'
        assert root + info['CFBundleExecutable'] in names
        assert any(n.startswith(root + 'Frameworks/Flutter.framework/') for n in names)
        assert any(n.startswith(root + 'Frameworks/cue_native.framework/') for n in names)
        assert not any('_CodeSignature/' in n or n.endswith('embedded.mobileprovision') for n in names)
        assert ipa.testzip() is None
    print('Verified unsigned device IPA layout; Sideloadly must sign it for your device.')

if __name__ == '__main__':
    verify(sys.argv[1])
