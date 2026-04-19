import { execFileSync, type ExecFileSyncOptionsWithStringEncoding } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

export function findProjectRoot(startDir: string = __dirname): string {
  let dir = startDir;
  while (dir !== path.parse(dir).root) {
    if (fs.existsSync(path.join(dir, 'build.zig'))) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  throw new Error('Could not find Zignocchio project root (no build.zig found)');
}

export function resolveZigExecutable(): string {
  return process.env.SOLANA_ZIG || process.env.ZIG || 'zig';
}

export function getDirectBuildArgs(
  exampleName: string,
  extraArgs: string[] = []
): string[] {
  return [`-Dexample=${exampleName}`, ...extraArgs];
}

export function buildExampleProgram(
  exampleName: string,
  opts: {
    projectRoot?: string;
    extraArgs?: string[];
    execOptions?: Omit<ExecFileSyncOptionsWithStringEncoding, 'cwd'>;
  } = {}
): void {
  const projectRoot = opts.projectRoot ?? findProjectRoot();
  const zig = resolveZigExecutable();
  const args = ['build', ...getDirectBuildArgs(exampleName, opts.extraArgs)];

  execFileSync(zig, args, {
    stdio: 'inherit',
    ...opts.execOptions,
    cwd: projectRoot,
  });
}
