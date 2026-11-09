import React, { useState } from 'react';
import { createPortal } from 'react-dom';
import { ZoomIn, ZoomOut, RotateCcw, X } from 'lucide-react';

export const ImageLightboxModal: React.FC<{
  src: string;
  alt?: string;
  onClose: () => void;
}> = ({ src, alt, onClose }) => {
  const [scale, setScale] = useState(1);

  const zoomIn = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    setScale(s => Math.min(+(s + 0.25).toFixed(2), 4));
  };
  const zoomOut = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    setScale(s => Math.max(+(s - 0.25).toFixed(2), 0.5));
  };
  const resetZoom = (e?: React.MouseEvent) => {
    e?.stopPropagation();
    setScale(1);
  };

  const handleWheel = (e: React.WheelEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (e.deltaY < 0) {
      setScale(s => Math.min(+(s + 0.15).toFixed(2), 4));
    } else {
      setScale(s => Math.max(+(s - 0.15).toFixed(2), 0.5));
    }
  };

  return createPortal(
    <div
      className="context-image-lightbox-modal"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
    >
      <div className="lightbox-dialog" onClick={e => e.stopPropagation()}>
        <div className="lightbox-controls">
          <button type="button" className="lightbox-btn" onClick={zoomOut} data-tip="Zoom Out (-)">
            <ZoomOut size={13} />
          </button>
          <span className="lightbox-scale-label">{Math.round(scale * 100)}%</span>
          <button type="button" className="lightbox-btn" onClick={zoomIn} data-tip="Zoom In (+)">
            <ZoomIn size={13} />
          </button>
          <button type="button" className="lightbox-btn" onClick={resetZoom} data-tip="Reset Zoom">
            <RotateCcw size={11} />
          </button>
          <button type="button" className="lightbox-btn lightbox-close" onClick={onClose} data-tip="Close">
            <X size={13} />
          </button>
        </div>
        <div className="lightbox-image-wrap" onWheel={handleWheel}>
          <img
            src={src}
            alt={alt || 'Image Preview'}
            style={{ transform: `scale(${scale})`, transition: 'transform 0.1s ease-out' }}
          />
        </div>
      </div>
    </div>,
    document.body
  );
};

