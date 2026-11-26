import React, { useMemo, useRef, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { MermaidDiagram } from './MermaidDiagram';
import { diffLines, isDiffLang } from './DiffCode';
import { storeActions } from '../store';
import { getMediaUrl } from '../utils/media';

interface Heading { level: number; text: string; slug: string }

const slugify = (text: string): string =>
  text.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-') || 'section';

/** Headings in document order, skipping fenced code; slugs deduped like GitHub. */
const parseHeadings = (md: string): Heading[] => {
  const out: Heading[] = [];
  const seen = new Map<string, number>();
  let inFence = false;
  for (const line of md.split('\n')) {
    if (/^\s*(```|~~~)/.test(line)) { inFence = !inFence; continue; }
    if (inFence) continue;
    const m = /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    if (!m) continue;
    const base = slugify(m[2]);
    const n = seen.get(base) || 0;
    seen.set(base, n + 1);
    out.push({ level: m[1].length, text: m[2].trim(), slug: n ? `${base}-${n}` : base });
  }
  return out;
};

/**
 * Read-only rendered preview for markdown files opened in the canvas.
 * Shares the chat renderer's pipeline (react-markdown + remark-gfm + mermaid)
 * but resolves links/images relative to the file's own directory: local file
 * links open in a canvas tab, remote links open externally, and relative
 * images ride the same loopback media URL the gallery uses.
 * A left outline rail renders one dash per heading (indent + width encode
 * depth); hovering a dash shows the themed title hint, clicking scrolls to it.
 */
export const MarkdownPreview: React.FC<{ content: string; filePath?: string }> = ({ content, filePath }) => {
  const baseDir = filePath ? filePath.slice(0, filePath.lastIndexOf('/')) : '';
  const headings = useMemo(() => parseHeadings(content), [content]);
  const hiRef = useRef(0);
  hiRef.current = 0;  // heading render order == parse order, each render
  const scrollRef = useRef<HTMLDivElement>(null);
  const [active, setActive] = useState(0);

  // Map a link/image target to an absolute local path, or null when it is
  // remote / an anchor / unresolvable (no base dir for relative targets).
  const resolveLocal = (href?: string): string | null => {
    if (!href || /^(https?:|mailto:|data:|#)/i.test(href)) return null;
    const clean = href.replace(/^file:\/\//, '').split('#')[0];
    if (!clean) return null;
    if (clean.startsWith('/')) return clean;
    if (!baseDir) return null;
    return `${baseDir}/${clean}`;
  };

  const onScroll = () => {
    const el = scrollRef.current;
    if (!el) return;
    const top = el.scrollTop + 90;
    let act = 0;
    headings.forEach((h, i) => {
      const node = document.getElementById(h.slug);
      if (node && node.offsetTop <= top) act = i;
    });
    setActive(act);
  };

  const heading = (level: number) => ({ children }: any) => {
    const h = headings[hiRef.current++];
    const Tag = `h${level}` as any;
    return <Tag id={h?.slug}>{children}</Tag>;
  };

  return (
    <div className="md-preview-scroll" ref={scrollRef} onScroll={onScroll}>
      {headings.length > 0 && (
        <nav className="md-outline-rail" aria-label="Document outline">
          {headings.map((h, i) => (
            <button
              key={`${h.slug}_${i}`}
              type="button"
              className={`md-outline-dash md-outline-l${h.level} ${i === active ? 'md-outline-active' : ''}`}
              title={h.text}
              onClick={() => document.getElementById(h.slug)?.scrollIntoView({ behavior: 'smooth', block: 'start' })}
            />
          ))}
        </nav>
      )}
      <div className="markdown-body md-preview-body">
        <ReactMarkdown
          remarkPlugins={[remarkGfm]}
          components={{
            h1: heading(1), h2: heading(2), h3: heading(3),
            h4: heading(4), h5: heading(5), h6: heading(6),
            a({ node, href, children, ...props }: any) {
              const local = resolveLocal(href);
              if (local) {
                return (
                  <a
                    href={href}
                    className="interactive-file-mention"
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      storeActions.openFileByPath(local);
                    }}
                    title={`Open ${local}`}
                    {...props}
                  >
                    {children}
                  </a>
                );
              }
              return <a href={href} target="_blank" rel="noreferrer" {...props}>{children}</a>;
            },
            img({ node, src, alt, ...props }: any) {
              const local = resolveLocal(typeof src === 'string' ? src : undefined);
              return <img src={local ? getMediaUrl(local) : src} alt={alt || ''} {...props} />;
            },
            code({ node, className, children, ...props }: any) {
              const match = /language-(\w+)/.exec(className || '');
              if (match && match[1] === 'mermaid') {
                return <MermaidDiagram code={String(children).replace(/\n$/, '')} />;
              }
              if (isDiffLang(match?.[1])) {
                return <code className="md-diff">{diffLines(String(children))}</code>;
              }
              // Block code keeps the default <pre> wrapper; inline code has no
              // language class. No extra <pre> here (would nest pre-in-pre).
              return <code className={className} {...props}>{children}</code>;
            },
          }}
        >
          {content}
        </ReactMarkdown>
      </div>
    </div>
  );
};