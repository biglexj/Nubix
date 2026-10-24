// Launch only the application window on Windows, including development builds.
#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

fn main() {
    nubix_lib::run()
}
