# setup\_env.sh

````bash
#!/usr/bin/env bash
set -e

# 1. تثبيت OpenJDK و Gradle وأدوات البناء الأساسية
sudo apt-get update
sudo apt-get install -y openjdk-11-jdk wget unzip git gradle

# 2. تنزيل أدوات SDK من Android
ANDROID_SDK_ROOT="$HOME/Android/Sdk"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
cd "$ANDROID_SDK_ROOT"
wget https://dl.google.com/android/repository/commandlinetools-linux-9477386_latest.zip -O cmdline-tools.zip
unzip cmdline-tools.zip
rm cmdline-tools.zip
mkdir -p cmdline-tools/latest
mv cmdline-tools/* cmdline-tools/latest/

# 3. إعداد المتغيرات البيئية تلقائيًا
grep -qxF 'export ANDROID_SDK_ROOT=$HOME/Android/Sdk' ~/.bashrc || \
  echo 'export ANDROID_SDK_ROOT=$HOME/Android/Sdk' >> ~/.bashrc
grep -qxF 'export PATH=$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH' ~/.bashrc || \
  echo 'export PATH=$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH' >> ~/.bashrc
source ~/.bashrc

# 4. قبول تراخيص Android SDK وتثبيت الأدوات اللازمة
yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses
sdkmanager --sdk_root="$ANDROID_SDK_ROOT" \
  "platform-tools" \
  "platforms;android-31" \
  "build-tools;31.0.0"

echo "✅ Android SDK و Platform Tools جاهزة للاستخدام."```  

---

# generate_project.sh
```bash
#!/usr/bin/env bash
set -e

if [ -z "${1}" ]; then
  echo "Usage: $0 <package_name> [app_name]"
  exit 1
fi
PACKAGE=$1                # مثال: com.example.adbapp
APP_NAME=${2:-AdbApp}      # اسم التطبيق

echo "📂 إنشاء مشروع Android باسم '$APP_NAME' بالحزمة '$PACKAGE'..."

# 1. إنشاء الهيكل الأساسي
mkdir -p "$APP_NAME/app/src/main/java/$(echo $PACKAGE | sed 's/\./\//g')"
mkdir -p "$APP_NAME/app/src/main/res/layout"
echo "$APP_NAME/" > "$APP_NAME/.gitignore"

# 2. ملفات Gradle
cat > "$APP_NAME/settings.gradle" <<EOF
rootProject.name = "$APP_NAME"
include ':app'
EOF

cat > "$APP_NAME/build.gradle" <<EOF
buildscript {
    repositories { google(); mavenCentral(); }
    dependencies { classpath "com.android.tools.build:gradle:7.0.4" }
}
allprojects {
    repositories { google(); mavenCentral(); }
}
EOF

# 3. تهيئة Gradle Wrapper
cd "$APP_NAME"
gradle wrapper --gradle-version 7.0.2 --distribution-type all

# 4. ملف build.gradle للموديول 'app'
cat > "app/build.gradle" <<EOF
plugins {
    id 'com.android.application'
    id 'kotlin-android'
}
android {
    compileSdk 31
    defaultConfig {
        applicationId "$PACKAGE"
        minSdk 21
        targetSdk 31
        versionCode 1
        versionName "1.0"
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }
    kotlinOptions { jvmTarget = '1.8' }
}
dependencies {
    // LibADB Android
    implementation "com.github.mikesafonov:libadb:2.4.0"
}
EOF

# 5. ملف AndroidManifest
cat > "app/src/main/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$PACKAGE">
    <application android:label="$APP_NAME">
        <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 6. MainActivity.kt
cat > "app/src/main/java/$(echo $PACKAGE | sed 's/\./\//g')/MainActivity.kt" <<EOF
package $PACKAGE

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.widget.*
import com.msa.libadb.LibAdb

class MainActivity : AppCompatActivity() {
    private lateinit var adb: LibAdb

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        adb = LibAdb(this)

        // حقول الـ UI
        val pairInput = findViewById<EditText>(R.id.pair_input)
        val pairBtn = findViewById<Button>(R.id.pair_btn)
        val pairResult = findViewById<TextView>(R.id.pair_result)

        pairBtn.setOnClickListener {
            pairResult.text = adb.execute("adb pair ${'$'}{pairInput.text}")
        }

        val connectInput = findViewById<EditText>(R.id.connect_input)
        val connectBtn = findViewById<Button>(R.id.connect_btn)
        val connectResult = findViewById<TextView>(R.id.connect_result)

        connectBtn.setOnClickListener {
            connectResult.text = adb.execute("adb connect ${'$'}{connectInput.text}")
        }

        val statusBtn = findViewById<Button>(R.id.status_btn)
        val usersLayout = findViewById<LinearLayout>(R.id.users_layout)

        statusBtn.setOnClickListener {
            usersLayout.removeAllViews()
            val output = adb.execute("adb shell pm list users")
            output.lines().forEach { line ->
                val id = line.substringAfter(":").trim()
                val row = layoutInflater.inflate(R.layout.user_row, usersLayout, false)
                val nameView = row.findViewById<TextView>(R.id.user_name)
                val activeIcon = row.findViewById<ImageView>(R.id.active_icon)
                val stopBtn = row.findViewById<Button>(R.id.stop_btn)
                val switchBtn = row.findViewById<Button>(R.id.switch_btn)
                val deleteBtn = row.findViewById<Button>(R.id.delete_btn)

                nameView.text = line
                // TODO: تعيين أيقونة خضراء للمستخدم النشط بناءً على الشرط
                usersLayout.addView(row)
            }
        }
    }
}
EOF

# 7. layout/activity_main.xml
cat > "app/src/main/res/layout/activity_main.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <LinearLayout
        android:orientation="vertical"
        android:padding="16dp"
        android:layout_width="match_parent"
        android:layout_height="wrap_content">

        <EditText
            android:id="@+id/pair_input"
            android:hint="IP:Port (pair)"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />
        <Button
            android:id="@+id/pair_btn"
            android:text="Pair"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content" />
        <TextView
            android:id="@+id/pair_result"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content" />

        <EditText
            android:id="@+id/connect_input"
            android:hint="IP:Port (connect)"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />
        <Button
            android:id="@+id/connect_btn"
            android:text="Connect"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content" />
        <TextView
            android:id="@+id/connect_result"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content" />

        <Button
            android:id="@+id/status_btn"
            android:text="Show Users"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content" />
        <LinearLayout
            android:id="@+id/users_layout"
            android:orientation="vertical"
            android:layout_width="match_parent"
            android:layout_height="wrap_content" />
    </LinearLayout>
</ScrollView>
EOF

echo "✅ تم إنشاء مشروع '$APP_NAME' بنجاح! يمكنك الآن تشغيل './gradlew assembleDebug' لمبناء الـ APK."```

````
