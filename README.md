# <img src="https://raw.githubusercontent.com/Orbitingpoint/OrbitExtraResources/main/icons/icon-192.png" width="40" height="40" alt="OrbitBuilder icon">rbitBuilder

## Usage

### Building an APK

**1. Select the APK**

Before building, you need to provide the original game APK.

Click the **Browse** button and navigate to the APK you want to use.

**2. Select your mods**

Once the APK has been loaded, you can choose which mods you want to bundle.

Hovering over a mod will display a short description of its functionality.

**3. Configure the required tools**

Press **Build**, you may encounter errors indicating that some required items are missing.

To fix it:

1. Open the **Tools** menu in the top bar.
2. Select **Tool Paths and Build Settings**.
3. Find the missing dependencies and input the path.

For example:

| Setting         | Path                                        |
| --------------- | ------------------------------------------- |
| AIR SDK folder  | `C:\AIRSDK\AIRSDK_51.4.1`                   |
| Java executable | `C:\java\jdk-25.0.1.8-hotspot\bin\java.exe` |
| FFDec.jar       | `C:\downloads\ffdec\ffdec.jar`              |


**4. Install the missing dependencies**

In particular, you may find that the AIR SDK and the ane folder are missing.

&nbsp;&nbsp;<img src="https://raw.githubusercontent.com/Orbitingpoint/OrbitExtraResources/main/icons/icon-48.png" width="10" height="10" alt="icon"> **AIR SDK:** You can download it from the [official AIR SDK documentation](https://airsdk.dev/docs/basics/install/windows).
    
&nbsp;&nbsp;<img src="https://raw.githubusercontent.com/Orbitingpoint/OrbitExtraResources/main/icons/icon-48.png" width="10" height="10" alt="icon"> **ANE files:** Not included in this repository because they contain native libraries used by the game to interact with the device.
&nbsp;&nbsp; A recreation of those can be found in the [OrbitAne repository](https://github.com/Orbitingpoint/OrbitAne).

Download the `out_shim` directory and extract it. Your directory structure should look something like this:

	C:\downloads\out_shim\\out_shim

**5. Verify the configurations**

Once all dependencies have been configured, click **Check Paths** to verify that everything is correctly set up.

If everything is configured correctly, you can proceed with the build.

**6. Locate the output**

Click **Build** to generate your APK.

The resulting file will be placed in the specified output folder.

---
## Compiling the Project

### Requirements

[Haxe](https://haxe.org) "Preferably, the latest version of Haxe."

and the following haxe libs:

&nbsp;&nbsp;<img src="https://raw.githubusercontent.com/Orbitingpoint/OrbitExtraResources/main/icons/icon-48.png" width="10" height="10" alt="icon"> [haxeui-core](https://github.com/haxeui/haxeui-core)<br>

&nbsp;&nbsp;<img src="https://raw.githubusercontent.com/Orbitingpoint/OrbitExtraResources/main/icons/icon-48.png" width="10" height="10" alt="icon"> [haxeui-hxwidgets](https://github.com/haxeui/hxwidgets)

All of which can be installed with the following command:

	haxelib install haxeui-core 1.7.0
	haxelib install haxeui-hxwidgets 1.7.0

Once you have all the requirements you can build the project with

	haxe build.hxml

Once the build process is complete, depending on your operating system, you may need to install additional dependencies before running the compiled application,

#### If you are on windows:
you will need to supply the DLLs required by hxWidgets in order to run, to do so follow [this guide](https://haxeui.org/getting-started/haxeui-hxwidgets/)

#### Linux:
Run the following command:

	apt-get install libwxgtk3.0-dev libwxbase3.0-dev libwxgtk-webview3.0-dev

#### OSX:

	brew update
	brew install wxwidgets