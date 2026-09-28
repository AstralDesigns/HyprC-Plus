import { useState, useEffect, type FC } from 'react';
import {
  User, Github, GitBranch, Key, Eye, EyeOff,
  ExternalLink, RefreshCw, Check, X, AlertTriangle,
  Loader, LogOut, Search, FolderGit2, ArrowUpRight, Lock, Globe,
} from 'lucide-react';
import { useStore, setStore } from '../store';
import { bridge } from '../bridge';

const PRIMARY      = 'var(--matugen-primary, #a0c9dc)';
const ON_PRIMARY   = 'var(--matugen-on-secondary, #1d343c)';
const INVERSE_PRI  = 'var(--matugen-inverse-primary, #a0c9dc)';
const COLOR5_AMBER = 'var(--wallust-color5, #BA8C40)';
const ERROR_COLOR  = 'var(--matugen-error, #ffb4ab)';

interface GitHubRepo {
  id: number;
  name: string;
  full_name: string;
  private: boolean;
  html_url: string;
  description: string | null;
  default_branch: string;
  updated_at: string;
}

export const ProfileModal: FC = () => {
  const [store] = useStore();

  const [tokenInput, setTokenInput]     = useState('');
  const [showToken, setShowToken]       = useState(false);
  const [authenticating, setAuth]       = useState(false);
  const [authError, setAuthError]       = useState('');
  const [repos, setRepos]               = useState<GitHubRepo[]>([]);
  const [loadingRepos, setLoadingRepos] = useState(false);
  const [repoSearch, setRepoSearch]     = useState('');

  // Sync tokenInput if already stored
  useEffect(() => {
    if (store.githubToken && !tokenInput) {
      setTokenInput(store.githubToken);
    }
  }, [store.githubToken]);

  // Fetch repositories whenever githubToken is valid and modal opens
  useEffect(() => {
    if (store.profileOpen && store.githubToken && store.githubUser) {
      fetchUserRepos(store.githubToken);
    }
  }, [store.profileOpen, store.githubToken, store.githubUser]);

  const fetchUserRepos = async (token: string) => {
    setLoadingRepos(true);
    try {
      const resp = await fetch('https://api.github.com/user/repos?per_page=100&sort=updated', {
        headers: {
          Authorization: `token ${token}`,
          Accept: 'application/vnd.github.v3+json',
        },
      });
      if (resp.ok) {
        const data = await resp.json();
        setRepos(Array.isArray(data) ? data : []);
      } else {
        console.warn('[ProfileModal] Failed to fetch repositories:', resp.status);
      }
    } catch (err) {
      console.warn('[ProfileModal] Error fetching repositories:', err);
    } finally {
      setLoadingRepos(false);
    }
  };

  const handleAuthenticate = async () => {
    const cleanToken = tokenInput.trim();
    if (!cleanToken) return;

    setAuth(true);
    setAuthError('');

    try {
      const resp = await fetch('https://api.github.com/user', {
        headers: {
          Authorization: `token ${cleanToken}`,
          Accept: 'application/vnd.github.v3+json',
        },
      });

      if (!resp.ok) {
        if (resp.status === 401) {
          throw new Error('Invalid personal access token. Please verify scopes and expiration.');
        }
        throw new Error(`GitHub API returned status ${resp.status}`);
      }

      const userData = await resp.json();
      setStore({
        githubToken: cleanToken,
        githubUser: {
          login: userData.login,
          name: userData.name || userData.login,
          avatar_url: userData.avatar_url,
          html_url: userData.html_url,
          bio: userData.bio || '',
          public_repos: userData.public_repos || 0,
        },
      });

      await fetchUserRepos(cleanToken);
    } catch (err: any) {
      setAuthError(err.message || 'Authentication failed. Please check network and token.');
    } finally {
      setAuth(false);
    }
  };

  const handleDisconnect = () => {
    setStore({
      githubToken: '',
      githubUser: null,
      selectedRepo: '',
    });
    setTokenInput('');
    setRepos([]);
    setAuthError('');
  };

  if (!store.profileOpen) return null;

  const user = store.githubUser;
  const filteredRepos = repos.filter(r =>
    r.name.toLowerCase().includes(repoSearch.toLowerCase()) ||
    (r.description && r.description.toLowerCase().includes(repoSearch.toLowerCase()))
  );

  return (
    <div
      onClick={() => setStore({ profileOpen: false })}
      style={{
        position: 'absolute',
        inset: 0,
        background: 'rgba(0,0,0,.65)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 100,
      }}
    >
      <div
        className="animate-fade-in"
        onClick={e => e.stopPropagation()}
        style={{
          width: '560px',
          maxHeight: '88vh',
          background: 'var(--matugen-on-secondary, #1d343c)',
          border: '1px solid var(--border-glass)',
          borderRadius: 'var(--radius-lg)',
          boxShadow: '0 20px 60px rgba(0,0,0,.7)',
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
          backdropFilter: 'blur(20px)',
        }}
      >

        {/* Header */}
        <div style={{
          padding: '16px 20px 12px',
          borderBottom: '1px solid var(--border-subtle)',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
        }}>
          <div style={{
            width: 34,
            height: 34,
            borderRadius: '50%',
            background: PRIMARY,
            color: ON_PRIMARY,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}>
            <User size={18} color={ON_PRIMARY} />
          </div>
          <div>
            <div style={{ fontWeight: 700, fontSize: '14px', color: 'var(--text-primary)' }}>
              User Profile &amp; VCS
            </div>
            <div style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
              {user ? `GitHub · @${user.login} connected` : 'GitHub Authentication & Repository Sync'}
            </div>
          </div>
        </div>

        {/* Content */}
        <div style={{
          flex: 1,
          overflowY: 'auto',
          padding: '16px 20px',
          scrollbarWidth: 'thin',
          display: 'flex',
          flexDirection: 'column',
          gap: '16px',
        }}>
          {!user ? (
            /* ── Connect GitHub View ── */
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div style={{
                padding: '14px',
                border: '1px solid var(--border-subtle)',
                background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 30%, transparent)',
                borderRadius: 'var(--radius-md)',
                display: 'flex',
                gap: '12px',
                alignItems: 'flex-start',
              }}>
                <div style={{
                  width: 32,
                  height: 32,
                  borderRadius: 'var(--radius-sm)',
                  background: 'color-mix(in srgb, var(--matugen-primary, #a0c9dc) 15%, transparent)',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  flexShrink: 0,
                }}>
                  <Github size={18} color={PRIMARY} />
                </div>
                <div>
                  <div style={{ fontSize: '12.5px', fontWeight: 700, color: 'var(--text-primary)' }}>
                    GitHub Authentication
                  </div>
                  <div style={{ fontSize: '11.5px', color: 'var(--text-secondary)', lineHeight: 1.5, marginTop: '3px' }}>
                    Paste a GitHub Personal Access Token (classic or fine-grained with <code>repo</code> + <code>read:user</code> scopes) to link your account. OAuth browser sign-in requires a registered GitHub App — PAT is the standard approach for desktop tools.
                  </div>
                </div>
              </div>

              {/* Token Input */}
              <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <label style={{ fontSize: '11px', fontWeight: 600, color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <Key size={11} /> Personal Access Token (PAT)
                  </label>
                  <a
                    href="https://github.com/settings/tokens/new?scopes=repo,read:user,user:email&description=HyprCandy%20Agent"
                    onClick={e => {
                      e.preventDefault();
                      bridge.openExternalUrl('https://github.com/settings/tokens/new?scopes=repo,read:user,user:email&description=HyprCandy%20Agent');
                    }}
                    style={{ fontSize: '10.5px', color: PRIMARY, display: 'flex', alignItems: 'center', gap: '3px', textDecoration: 'none' }}
                  >
                    Generate on GitHub <ExternalLink size={10} />
                  </a>
                </div>

                <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
                  <input
                    type={showToken ? 'text' : 'password'}
                    value={tokenInput}
                    onChange={e => setTokenInput(e.target.value)}
                    onKeyDown={e => e.key === 'Enter' && handleAuthenticate()}
                    placeholder="ghp_... or github_pat_..."
                    style={{
                      width: '100%',
                      padding: '8px 40px 8px 12px',
                      background: 'var(--bg-input)',
                      border: '1px solid var(--border-subtle)',
                      borderRadius: 'var(--radius-sm)',
                      color: 'var(--text-primary)',
                      fontSize: '12px',
                      fontFamily: 'var(--font-mono)',
                      outline: 'none',
                    }}
                  />
                  <button
                    type="button"
                    onClick={() => setShowToken(!showToken)}
                    style={{
                      position: 'absolute',
                      right: '10px',
                      background: 'transparent',
                      border: 'none',
                      color: 'var(--text-muted)',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                    }}
                  >
                    {showToken ? <EyeOff size={14} /> : <Eye size={14} />}
                  </button>
                </div>

                {authError && (
                  <div style={{ fontSize: '11px', color: ERROR_COLOR, display: 'flex', alignItems: 'center', gap: '5px', marginTop: '4px' }}>
                    <AlertTriangle size={12} /> {authError}
                  </div>
                )}
              </div>

              {/* Submit Button */}
              <button
                type="button"
                onClick={handleAuthenticate}
                disabled={authenticating || !tokenInput.trim()}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '8px',
                  padding: '9px 16px',
                  borderRadius: 'var(--radius-sm)',
                  background: PRIMARY,
                  border: 'none',
                  color: ON_PRIMARY,
                  fontSize: '12px',
                  fontWeight: 700,
                  cursor: authenticating || !tokenInput.trim() ? 'not-allowed' : 'pointer',
                  opacity: authenticating || !tokenInput.trim() ? 0.6 : 1,
                  transition: 'opacity 0.15s ease',
                }}
              >
                {authenticating ? (
                  <>
                    <Loader size={13} className="animate-spin" /> Authenticating…
                  </>
                ) : (
                  <>
                    <Github size={13} /> Connect GitHub Account
                  </>
                )}
              </button>
            </div>
          ) : (
            /* ── Authenticated User & Repositories View ── */
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {/* Profile Card */}
              <div style={{
                padding: '14px',
                borderRadius: 'var(--radius-md)',
                background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 30%, transparent)',
                border: '1px solid var(--border-subtle)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                  <img
                    src={user.avatar_url}
                    alt={user.login}
                    style={{
                      width: 44,
                      height: 44,
                      borderRadius: '50%',
                      border: `2px solid ${PRIMARY}`,
                      objectFit: 'cover',
                    }}
                  />
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                      <span style={{ fontSize: '13.5px', fontWeight: 700, color: 'var(--text-primary)' }}>
                        {user.name || user.login}
                      </span>
                      <span style={{
                        fontSize: '9.5px',
                        padding: '1px 6px',
                        borderRadius: 'var(--radius-full)',
                        background: 'color-mix(in srgb, #10B981 18%, transparent)',
                        color: '#10B981',
                        fontWeight: 700,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px',
                      }}>
                        <span style={{ width: 5, height: 5, borderRadius: '50%', background: '#10B981' }} /> Connected
                      </span>
                    </div>
                    <div style={{ fontSize: '11px', color: 'var(--text-muted)', marginTop: '1px' }}>
                      @{user.login} {user.public_repos !== undefined ? `· ${user.public_repos} public repos` : ''}
                    </div>
                    {user.bio && (
                      <div style={{ fontSize: '10.5px', color: 'var(--text-secondary)', marginTop: '3px' }}>
                        {user.bio}
                      </div>
                    )}
                  </div>
                </div>

                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <button
                    type="button"
                    onClick={() => bridge.openExternalUrl(user.html_url)}
                    style={{
                      background: 'transparent',
                      border: '1px solid var(--border-subtle)',
                      borderRadius: 'var(--radius-sm)',
                      padding: '5px 8px',
                      color: 'var(--text-secondary)',
                      fontSize: '11px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px',
                    }}
                    title="View GitHub Profile"
                  >
                    Profile <ArrowUpRight size={11} />
                  </button>
                  <button
                    type="button"
                    onClick={handleDisconnect}
                    style={{
                      background: 'transparent',
                      border: `1px solid color-mix(in srgb, ${ERROR_COLOR} 40%, transparent)`,
                      borderRadius: 'var(--radius-sm)',
                      padding: '5px 8px',
                      color: ERROR_COLOR,
                      fontSize: '11px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px',
                    }}
                    title="Disconnect GitHub account"
                  >
                    <LogOut size={11} /> Disconnect
                  </button>
                </div>
              </div>

              {/* ── Active Repository Integration Section ── */}
              <div>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                  <div style={{ fontSize: '10.5px', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '.05em' }}>
                    Repository Integration (Target for direct pushing)
                  </div>
                  <button
                    type="button"
                    onClick={() => store.githubToken && fetchUserRepos(store.githubToken)}
                    disabled={loadingRepos}
                    style={{
                      background: 'transparent',
                      border: 'none',
                      color: PRIMARY,
                      fontSize: '10.5px',
                      cursor: 'pointer',
                      display: 'flex',
                      alignItems: 'center',
                      gap: '4px',
                    }}
                  >
                    <RefreshCw size={10} className={loadingRepos ? 'animate-spin' : ''} /> Refresh
                  </button>
                </div>

                {/* Search Bar */}
                <div style={{ position: 'relative', display: 'flex', alignItems: 'center', marginBottom: '8px' }}>
                  <Search size={12} color="var(--text-muted)" style={{ position: 'absolute', left: '10px' }} />
                  <input
                    type="text"
                    value={repoSearch}
                    onChange={e => setRepoSearch(e.target.value)}
                    placeholder="Search repositories…"
                    style={{
                      width: '100%',
                      padding: '6px 12px 6px 28px',
                      background: 'var(--bg-input)',
                      border: '1px solid var(--border-subtle)',
                      borderRadius: 'var(--radius-sm)',
                      color: 'var(--text-primary)',
                      fontSize: '11.5px',
                      outline: 'none',
                    }}
                  />
                  {repoSearch && (
                    <button
                      type="button"
                      onClick={() => setRepoSearch('')}
                      style={{
                        position: 'absolute',
                        right: '8px',
                        background: 'transparent',
                        border: 'none',
                        color: 'var(--text-muted)',
                        cursor: 'pointer',
                      }}
                    >
                      <X size={12} />
                    </button>
                  )}
                </div>

                {/* Repositories List */}
                <div style={{
                  maxHeight: '220px',
                  overflowY: 'auto',
                  borderRadius: 'var(--radius-sm)',
                  border: '1px solid var(--border-subtle)',
                  background: 'color-mix(in srgb, var(--matugen-surface, #0c1014) 20%, transparent)',
                  display: 'flex',
                  flexDirection: 'column',
                  scrollbarWidth: 'thin',
                }}>
                  {loadingRepos ? (
                    <div style={{ padding: '24px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '11.5px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
                      <Loader size={13} className="animate-spin" /> Loading repositories…
                    </div>
                  ) : filteredRepos.length === 0 ? (
                    <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-muted)', fontSize: '11.5px' }}>
                      No repositories found
                    </div>
                  ) : (
                    filteredRepos.map(repo => {
                      const isSelected = store.selectedRepo === repo.full_name;
                      return (
                        <div
                          key={repo.id}
                          onClick={() => setStore({ selectedRepo: isSelected ? '' : repo.full_name })}
                          style={{
                            padding: '8px 12px',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'space-between',
                            borderBottom: '1px solid var(--border-subtle)',
                            cursor: 'pointer',
                            background: isSelected
                              ? `color-mix(in srgb, ${PRIMARY} 14%, transparent)`
                              : 'transparent',
                            transition: 'background 0.15s ease',
                          }}
                        >
                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', minWidth: 0 }}>
                            {repo.private ? <Lock size={12} color="var(--text-muted)" /> : <Globe size={12} color="var(--text-muted)" />}
                            <div style={{ minWidth: 0 }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                                <span style={{
                                  fontSize: '11.5px',
                                  fontWeight: isSelected ? 700 : 500,
                                  color: isSelected ? PRIMARY : 'var(--text-primary)',
                                  whiteSpace: 'nowrap',
                                  overflow: 'hidden',
                                  textOverflow: 'ellipsis',
                                }}>
                                  {repo.name}
                                </span>
                                <span style={{
                                  fontSize: '9px',
                                  padding: '1px 5px',
                                  borderRadius: 'var(--radius-full)',
                                  background: 'var(--border-subtle)',
                                  color: 'var(--text-muted)',
                                }}>
                                  {repo.default_branch}
                                </span>
                              </div>
                              {repo.description && (
                                <div style={{
                                  fontSize: '10px',
                                  color: 'var(--text-muted)',
                                  whiteSpace: 'nowrap',
                                  overflow: 'hidden',
                                  textOverflow: 'ellipsis',
                                  maxWidth: '320px',
                                }}>
                                  {repo.description}
                                </div>
                              )}
                            </div>
                          </div>

                          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexShrink: 0 }}>
                            <button
                              type="button"
                              onClick={e => {
                                e.stopPropagation();
                                bridge.openExternalUrl(repo.html_url);
                              }}
                              style={{
                                background: 'transparent',
                                border: 'none',
                                color: 'var(--text-muted)',
                                cursor: 'pointer',
                                padding: '2px',
                              }}
                              title="Open on GitHub"
                            >
                              <ArrowUpRight size={12} />
                            </button>
                            <div style={{
                              width: 16,
                              height: 16,
                              borderRadius: '50%',
                              border: isSelected ? `2px solid ${PRIMARY}` : '1px solid var(--border-subtle)',
                              background: isSelected ? PRIMARY : 'transparent',
                              display: 'flex',
                              alignItems: 'center',
                              justifyContent: 'center',
                            }}>
                              {isSelected && <Check size={10} color={ON_PRIMARY} />}
                            </div>
                          </div>
                        </div>
                      );
                    })
                  )}
                </div>
              </div>

              {/* Push & Sync Readiness Card */}
              <div style={{
                padding: '12px 14px',
                borderRadius: 'var(--radius-md)',
                background: `color-mix(in srgb, ${PRIMARY} 8%, transparent)`,
                border: `1px solid color-mix(in srgb, ${PRIMARY} 25%, transparent)`,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
              }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '9px' }}>
                  <GitBranch size={16} color={PRIMARY} />
                  <div>
                    <div style={{ fontSize: '11.5px', fontWeight: 600, color: 'var(--text-primary)' }}>
                      {store.selectedRepo ? `Target: ${store.selectedRepo}` : 'No target repository selected'}
                    </div>
                    <div style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                      {store.selectedRepo
                        ? 'Project updates and file edits can be directly pushed to this repository.'
                        : 'Select a repository above to enable direct project syncing.'}
                    </div>
                  </div>
                </div>

                {store.selectedRepo && (
                  <span style={{
                    fontSize: '10px',
                    fontWeight: 700,
                    color: PRIMARY,
                    background: `color-mix(in srgb, ${PRIMARY} 18%, transparent)`,
                    padding: '3px 8px',
                    borderRadius: 'var(--radius-full)',
                  }}>
                    Ready
                  </span>
                )}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
