import * as vscode from 'vscode';
import path = require('path');


function createDebugAdapterDescriptorFactory(context: vscode.ExtensionContext): vscode.DebugAdapterDescriptorFactory {
    return {
        createDebugAdapterDescriptor(
            session: vscode.DebugSession,
            executable: vscode.DebugAdapterExecutable | undefined
        ): vscode.ProviderResult<vscode.DebugAdapterDescriptor> {
            const ROOT = process.env.VSCODE_EXTENSION_PATH || context.extensionPath;
            const runtime = `./LuaJIT/src/luajit.exe`;
            const runtimeArgs: string[] = [
                `luada.lua`,
                '--DEBUG'
            ];

            const ch = vscode.window.createOutputChannel("LuaDA");
            ch.appendLine(`launch luada... ${runtime} [${runtimeArgs}]`);

            return new vscode.DebugAdapterExecutable(runtime, runtimeArgs, { cwd: ROOT });
        }
    };
}

export function activate(context: vscode.ExtensionContext) {
    console.log('activate luada');
    context.subscriptions.push(vscode.debug.registerDebugAdapterDescriptorFactory('luada', createDebugAdapterDescriptorFactory(context)));
}

export function deactivate() { }
