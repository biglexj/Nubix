import { invoke, isTauri } from "@tauri-apps/api/core";
export type Account = {
  id: string;
  name: string;
  provider: string;
  email: string | null;
  root_label: string;
};
export type RemoteFolder = { Name: string; ID: string; Path: string };
export type Comparison = {
  identical: number;
  local_only: number;
  cloud_only: number;
  different: number;
  errors: number;
};
export type Pair = {
  id: string;
  local: string;
  remote: string;
  accountId: string;
  rootId: string;
};
export type Job = {
  running: boolean;
  pid: number;
  updated: string;
  folders: {
    id: string;
    state: string;
    transferred: number;
    bytes: number;
    total_bytes: number;
    comparison: Comparison | null;
    error: string | null;
  }[];
};
export async function call<T>(
  command: string,
  args?: Record<string, unknown>,
): Promise<T> {
  if (!isTauri())
    throw new Error(
      "Abre la ventana de Nubix para conectar y acceder a Drive. Esta pestaña muestra la interfaz.",
    );
  return invoke<T>(command, args);
}
export const api = {
  preferences: () => call<unknown[] | null>("preferences_load"),
  savePreferences: (folders: unknown[]) =>
    call<void>("preferences_save", { folders }),
  job: () => call<Job | null>("job_status"),
  accounts: () => call<Account[]>("cloud_accounts"),
  existing: () => call<{ name: string; provider: string }[]>("cloud_existing"),
  connect: (jsonPath: string, name: string) =>
    call<Account>("cloud_connect", { jsonPath, name }),
  import: (name: string) => call<Account>("cloud_import", { name }),
  disconnect: (id: string) => call<void>("cloud_disconnect", { id }),
  cancel: () => call<void>("cloud_cancel"),
  folders: (accountId: string, rootId: string) =>
    call<RemoteFolder[]>("cloud_folders", { accountId, rootId }),
  compare: (pair: Pair) => call<Comparison>("cloud_compare", { pair }),
  upload: (pair: Pair) => call<Comparison>("cloud_upload", { pair }),
};
