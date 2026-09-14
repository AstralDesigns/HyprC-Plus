/**
 * Agent Function-Calling Tools Definitions (OpenAI-compatible schema for web-llm)
 */

export interface ToolDefinition {
  type: 'function';
  function: {
    name: string;
    description: string;
    parameters: {
      type: 'object';
      properties: Record<string, {
        type: string;
        description: string;
        items?: { type: string };
      }>;
      required: string[];
    };
  };
}

export const AGENT_TOOLS: ToolDefinition[] = [
  {
    type: 'function',
    function: {
      name: 'web_search',
      description: 'Search the web using local SearXNG metasearch engine to fetch real-time facts, documentation, URLs, and answers.',
      parameters: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: 'The search query or keywords to look up.'
          }
        },
        required: ['query']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'read_file',
      description: 'Read the text content of a file on the local file system. For large files, use offset/limit to read a slice instead of the whole file.',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: 'The absolute or relative path to the file to read.'
          },
          offset: {
            type: 'number',
            description: 'Optional 1-based line number to start reading from. Omit to read from the top.'
          },
          limit: {
            type: 'number',
            description: 'Optional maximum number of lines to read from offset. Omit to read to the end (or a safe cap for very large files).'
          }
        },
        required: ['path']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'fetch_url',
      description: 'Fetch a specific web page or documentation URL and return its readable text content (not just a search snippet). Use this after web_search to actually read a promising result, or when the user gives you a direct URL to look at.',
      parameters: {
        type: 'object',
        properties: {
          url: {
            type: 'string',
            description: 'The absolute URL to fetch (must start with http:// or https://).'
          }
        },
        required: ['url']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'write_file',
      description: 'Create or overwrite a file on the local file system with new content.',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: 'The path where the file should be written.'
          },
          content: {
            type: 'string',
            description: 'The full text content to write into the file.'
          }
        },
        required: ['path', 'content']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'list_directory',
      description: 'List files and subdirectories inside a given directory.',
      parameters: {
        type: 'object',
        properties: {
          path: {
            type: 'string',
            description: 'The directory path to list (e.g., "." or absolute path).'
          }
        },
        required: ['path']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'exec_command',
      description: 'Execute a bash shell command on the host machine. Use with caution for builds, git operations, or running tests.',
      parameters: {
        type: 'object',
        properties: {
          command: {
            type: 'string',
            description: 'The bash shell command line to run.'
          },
          cwd: {
            type: 'string',
            description: 'Optional working directory in which to execute the command.'
          }
        },
        required: ['command']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'plan_update',
      description: 'Create or update the visible task plan while working. Use concise ordered tasks and mark exactly one active task when work remains.',
      parameters: {
        type: 'object',
        properties: {
          tasks: { type: 'array', description: 'Ordered plan task objects with id, title, and status.', items: { type: 'object' } as any },
        },
        required: ['tasks'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'task_complete',
      description: 'Call this only when the user task is fully complete. Include a concise summary of what was done and any remaining limitation.',
      parameters: {
        type: 'object',
        properties: {
          summary: { type: 'string', description: 'A concise completion summary for the user.' },
          remaining: { type: 'string', description: 'Optional remaining limitation or empty string.' },
        },
        required: ['summary'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'take_screenshot',
      description: 'Take a screenshot of the current Wayland display using grim. Returns the saved file path. Optionally specify a region as "x,y,width,height".',
      parameters: {
        type: 'object',
        properties: {
          region: {
            type: 'string',
            description: 'Optional screen region to capture in format "x,y,width,height" (e.g. "0,0,1920,1080"). Leave empty to capture the full screen.'
          }
        },
        required: []
      }
    }
  }
];

export const AGENT_SYSTEM_PROMPT = `You are the HyprCandy Agent, an intelligent local AI assistant embedded directly into the HyprCandy launcher on Hyprland via WebKitGTK and WebGPU.
You have access to native tools:
- web_search: search the web via SearXNG (returns snippets/links, not full page text)
- fetch_url: fetch a specific URL and read its actual page/doc content
- read_file: inspect files on disk (use offset/limit to read a slice of a large file instead of the whole thing)
	- write_file: propose a complete file replacement; the user reviews it before saving
- list_directory: inspect project directories
	- exec_command: propose a bash command (e.g. sed/grep/python/tee for anything not covered by a dedicated tool); the user reviews it before execution
	- take_screenshot: capture the current Wayland display using grim
	- task_complete: signal that the requested task is fully complete

	When the user asks you to write or change code:
1. First read the relevant files if necessary.
2. Present a clear explanation of your proposed changes.
3. Use write_file or propose shell commands.
	4. When writing code, provide complete and clean code. Always provide both a valid path and complete string content for write_file. Use the supplied project root exactly; if a read or directory listing fails, do not repeat the same call—correct the path or explain the limitation.

You are theme-aware: you know the user's Hyprland setup uses Matugen (Material You) for primary/secondary colors and Wallust for terminal colors (color0-color15).

You are running through a local text-generation model, not a hosted API with guaranteed native tool_calls. When you need a tool, emit exactly one JSON object inside a <tool_call>...</tool_call> block and do not merely describe the action:
<tool_call>{"name":"read_file","arguments":{"path":"/absolute/path"}}</tool_call>
Supported tool names and arguments are:
- read_file: {"path":"...","offset":1,"limit":200}
- list_directory: {"path":"..."}
- web_search: {"query":"..."}
- fetch_url: {"url":"https://..."}
- write_file: {"path":"...","content":"..."}
- exec_command: {"command":"...","cwd":"..."}
- take_screenshot: {"region":"x,y,width,height"}
	Use the project context supplied below as authoritative. For project questions, inspect the supplied context first; do not invent project names. After a tool result is supplied, continue the same task and either use another tool or answer the user.
	Call task_complete only after the task is actually finished; do not end an agentic task with a progress update alone.

Format normal responses in clean Markdown with clear headings and code blocks.`;
