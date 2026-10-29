"""Generate platform scaffolds without touching maintained Dart sources."""
import pathlib, shutil, subprocess, tempfile
root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([shutil.which('flutter') or 'flutter', 'create', '--platforms=android,windows', '--org',
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
s = manifest.read_text(encoding='utf-8')
if 'android:allowBackup=' not in s:
    s = s.replace('<application', '<application android:allowBackup="false"', 1)
manifest.write_text(s, encoding='utf-8')
runner = root / 'windows/runner/main.cpp'
s = runner.read_text(encoding='utf-8').replace('L"liubai_diary"', 'L"Liubai Diary"')
runner.write_text(s, encoding='utf-8')

# System-native HTTPS transports. These sources contain no credentials.
activity = root / 'android/app/src/main/kotlin/app/liubai/liubai_diary/MainActivity.kt'
activity.parent.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / 'tool/native/NetworkActivity.kt', activity)
shutil.copyfile(root / 'tool/native/native_http.cpp', root / 'windows/runner/native_http.cpp')
cmake = root / 'windows/CMakeLists.txt'
s = cmake.read_text(encoding='utf-8')
if 'add_library(liubai_network' not in s:
    s += '\nadd_library(liubai_network SHARED "runner/native_http.cpp")\ntarget_link_libraries(liubai_network PRIVATE winhttp)\ninstall(TARGETS liubai_network RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)\n'
cmake.write_text(s, encoding='utf-8')
