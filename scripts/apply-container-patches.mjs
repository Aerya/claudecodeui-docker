import fs from 'node:fs';

const providerLoginPath = 'upstream/src/components/provider-auth/view/ProviderLoginModal.tsx';
const claudeAuthPath = 'upstream/server/modules/providers/list/claude/claude-auth.provider.ts';
const rootUnsafeCommand = 'claude --dangerously-skip-permissions /login';
const loginCommand = 'claude auth login';

let providerLogin = fs.readFileSync(providerLoginPath, 'utf8');

if (providerLogin.includes(rootUnsafeCommand)) {
  providerLogin = providerLogin.replace(rootUnsafeCommand, loginCommand);
} else if (!providerLogin.includes(loginCommand)) {
  throw new Error(`Unable to patch Claude login command in ${providerLoginPath}`);
}

fs.writeFileSync(providerLoginPath, providerLogin);

let claudeAuth = fs.readFileSync(claudeAuthPath, 'utf8');
const authTokenPattern = /(\s+if \(process\.env\.ANTHROPIC_AUTH_TOKEN\?\.trim\(\)\) \{\r?\n\s+return \{ authenticated: true, email: 'Auth Token', method: 'api_key' \};\r?\n\s+\}\r?\n)/;

if (!claudeAuth.includes('process.env.CLAUDE_CODE_OAUTH_TOKEN?.trim()')) {
  if (!authTokenPattern.test(claudeAuth)) {
    throw new Error(`Unable to patch Claude OAuth token detection in ${claudeAuthPath}`);
  }
  claudeAuth = claudeAuth.replace(authTokenPattern, `$1
    if (process.env.CLAUDE_CODE_OAUTH_TOKEN?.trim()) {
      return { authenticated: true, email: 'OAuth Token', method: 'oauth_token' };
    }
`);
}

fs.writeFileSync(claudeAuthPath, claudeAuth);

console.log('Container compatibility patches applied successfully.');
