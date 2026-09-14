import React, { useState, useRef, useEffect } from 'react';
import { X, Image as ImageIcon, Video, Plus, Check } from 'lucide-react';
import { useStore, storeActions, FileSystemItem } from '../store';
import { getMediaUrl } from '../utils/media';

interface MediaGalleryProps {
  mediaItems: FileSystemItem[];
  mediaType: 'image' | 'video';
}

export const MediaGallery: React.FC<MediaGalleryProps> = ({ mediaItems, mediaType }) => {
  const [store] = useStore();
  const [lightboxIndex, setLightboxIndex] = useState<number | null>(null);
  const wheelTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const openLightbox = (index: number) => {
    setLightboxIndex(index);
  };

  const closeLightbox = () => {
    setLightboxIndex(null);
  };

  const navigateLightbox = (direction: 'prev' | 'next') => {
    if (lightboxIndex === null) return;
    if (direction === 'prev') {
      const newIndex = lightboxIndex > 0 ? lightboxIndex - 1 : mediaItems.length - 1;
      setLightboxIndex(newIndex);
    } else {
      const newIndex = lightboxIndex < mediaItems.length - 1 ? lightboxIndex + 1 : 0;
      setLightboxIndex(newIndex);
    }
  };

  // Keyboard navigation when lightbox is active
  useEffect(() => {
    if (lightboxIndex === null) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') closeLightbox();
      else if (e.key === 'ArrowLeft') navigateLightbox('prev');
      else if (e.key === 'ArrowRight') navigateLightbox('next');
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [lightboxIndex, mediaItems.length]);

  const isInContext = (path: string): boolean => {
    return store.contextImages.some(img => img.path === path);
  };

  const toggleContext = (e: React.MouseEvent, item: FileSystemItem) => {
    e.preventDefault();
    e.stopPropagation();
    if (mediaType !== 'image') return;
    if (isInContext(item.path)) {
      storeActions.removeContextImage(item.path);
    } else {
      storeActions.addContextImage({ path: item.path, data: getMediaUrl(item.path) });
    }
  };

  const currentItem = lightboxIndex !== null ? mediaItems[lightboxIndex] : null;

  return (
    <div className="media-gallery-container">
      <div className="media-gallery-grid">
        {mediaItems.map((item, index) => {
          const inContext = mediaType === 'image' ? isInContext(item.path) : false;
          return (
            <div
              key={item.path}
              className="media-card group"
              onClick={() => openLightbox(index)}
              title={item.name}
            >
              {mediaType === 'image' ? (
                <img
                  src={getMediaUrl(item.path)}
                  alt={item.name}
                  className="media-thumb"
                  loading="lazy"
                  onError={(e) => {
                    (e.target as HTMLImageElement).src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="%231a232a"/><text x="50" y="50" text-anchor="middle" fill="%238da8b5" font-size="12">Image</text></svg>';
                  }}
                />
              ) : (
                <video
                  src={`${getMediaUrl(item.path)}#t=0.001`}
                  className="media-thumb"
                  preload="metadata"
                  muted
                  playsInline
                />
              )}

              <div className="media-card-overlay">
                {mediaType === 'image' && (
                  <div className="media-card-actions">
                    <button
                      type="button"
                      onClick={(e) => toggleContext(e, item)}
                      className={`context-badge-btn ${inContext ? 'active' : ''}`}
                      title={inContext ? 'Remove from agent context' : 'Add to agent context'}
                    >
                      {inContext ? <Check size={12} /> : <Plus size={12} />}
                      <span>{inContext ? 'In Context' : 'Context'}</span>
                    </button>
                  </div>
                )}
                <div className="media-card-footer">
                  <span className="media-card-name">{item.name}</span>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {lightboxIndex !== null && currentItem && (
        <div className="media-lightbox-overlay" onClick={closeLightbox}>
          <button
            type="button"
            className="lightbox-close-btn"
            onClick={closeLightbox}
            title="Close (Esc)"
          >
            <X size={20} />
          </button>

          {mediaItems.length > 1 && (
            <>
              <button
                type="button"
                className="lightbox-nav-btn prev"
                onClick={(e) => {
                  e.stopPropagation();
                  navigateLightbox('prev');
                }}
                title="Previous"
              >
                ‹
              </button>
              <button
                type="button"
                className="lightbox-nav-btn next"
                onClick={(e) => {
                  e.stopPropagation();
                  navigateLightbox('next');
                }}
                title="Next"
              >
                ›
              </button>
            </>
          )}

          <div className="lightbox-content" onClick={(e) => e.stopPropagation()}>
            {mediaType === 'image' ? (
              <img
                src={getMediaUrl(currentItem.path)}
                alt={currentItem.name}
                className="lightbox-media"
              />
            ) : (
              <video
                src={getMediaUrl(currentItem.path)}
                controls
                autoPlay
                playsInline
                className="lightbox-media"
              />
            )}
          </div>

          <div className="lightbox-caption">
            <span>{lightboxIndex + 1} / {mediaItems.length} — {currentItem.name}</span>
            {mediaType === 'image' && (
              <button
                type="button"
                className={`caption-context-btn ${isInContext(currentItem.path) ? 'active' : ''}`}
                onClick={(e) => toggleContext(e, currentItem)}
              >
                {isInContext(currentItem.path) ? 'In Agent Context' : '+ Add to Agent Context'}
              </button>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
