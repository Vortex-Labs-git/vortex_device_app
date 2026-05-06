@echo off
echo Creating device_detail folder structure and files...

:: Create the nested directories
mkdir "lib\screens\device_detail\widgets" 2>nul

:: Create the main screen file
type nul > "lib\screens\device_detail\device_detail_screen.dart"

:: Create the widget files
type nul > "lib\screens\device_detail\widgets\device_app_bar.dart"
type nul > "lib\screens\device_detail\widgets\device_info_card.dart"
type nul > "lib\screens\device_detail\widgets\mode_toggle_card.dart"
type nul > "lib\screens\device_detail\widgets\control_mode_card.dart"
type nul > "lib\screens\device_detail\widgets\valve_control_card.dart"
type nul > "lib\screens\device_detail\widgets\schedule_card.dart"
type nul > "lib\screens\device_detail\widgets\sensor_card.dart"
type nul > "lib\screens\device_detail\widgets\change_wifi_button.dart"
type nul > "lib\screens\device_detail\widgets\motor_calibration_button.dart"

echo.
echo Folder structure and empty files created successfully!
pause