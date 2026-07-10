#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Mostrar consola si existe el archivo "mostrar_consola.txt" junto al .exe
  // (sirve para ver errores al arrancar en Release).
  wchar_t module_path[MAX_PATH];
  if (::GetModuleFileNameW(nullptr, module_path, MAX_PATH) != 0) {
    std::wstring path(module_path);
    const size_t slash = path.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
      path = path.substr(0, slash + 1) + L"mostrar_consola.txt";
      if (::GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES) {
        CreateAndAttachConsole();
      }
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  } else if (::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Tata.Manager", origin, size)) {
    ::MessageBoxW(
        nullptr,
        L"No se pudo crear la ventana de Tata.Manager.\n"
        L"Verificá que exista la carpeta data junto al .exe.",
        L"Tata.Manager",
        MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
