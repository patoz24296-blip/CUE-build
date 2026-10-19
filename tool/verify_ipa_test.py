import contextlib
import io
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from verify_ipa import verify

class IpaTests(unittest.TestCase):
    def make(self, path, platform='iPhoneOS', signature=False):
        root = 'Payload/CUE.app/'
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(root + 'Info.plist', plistlib.dumps(dict(CFBundlePackageType='APPL', CFBundleIdentifier='studio.cue.cue', CFBundleSupportedPlatforms=[platform], CFBundleExecutable='Runner')))
            for file in ['Runner', 'Frameworks/Flutter.framework/Flutter', 'Frameworks/cue_native.framework/cue_native']:
                archive.writestr(root + file, b'fixture')
            if signature:
                archive.writestr(root + '_CodeSignature/CodeResources', b'stale')
    def test_device_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            self.make(path)
            with contextlib.redirect_stdout(io.StringIO()): verify(path)
    def test_simulator_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            self.make(path, platform='iPhoneSimulator')
            with self.assertRaises(AssertionError): verify(path)
    def test_stale_signature_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'test.ipa'
            self.make(path, signature=True)
            with self.assertRaises(AssertionError): verify(path)

if __name__ == '__main__': unittest.main()
