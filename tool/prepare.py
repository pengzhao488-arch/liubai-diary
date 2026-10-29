"""Generate platform scaffolds without touching maintained Dart sources."""
import pathlib, shutil, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run(['flutter', 'create', '--platforms=android,windows', '--org',
                    'app.liubai', '--project-name', 'liubai_diary', tmp], check=True, shell=False)
    for platform in ('android', 'windows'):
        target = root / platform
        if not target.exists():
            shutil.copytree(pathlib.Path(tmp) / platform, target)
manifest = root / 'android/app/src/main/AndroidManifest.xml'
s = manifest.read_text(encoding='utf-8')
s = s.replace('android:label="liubai_diary"', 'android:label="留白日记"')
if 'android.permission.INTERNET' not in s:
    s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
manifest.write_text(s, encoding='utf-8')
# Keep private diary data out of Android's automatic device backup.
s = manifest.read_text(encoding='utf-8').replace('<application', '<application android:allowBackup="false"', 1)
manifest.write_text(s, encoding='utf-8')
runner = root / 'windows/runner/main.cpp'
s = runner.read_text(encoding='utf-8').replace('L"liubai_diary"', 'L"Liubai Diary"')
runner.write_text(s, encoding='utf-8')
