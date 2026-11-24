import React, { useMemo } from 'react';

export interface SliderTick {
  value: number; // Numeric value, or -1 for Uncapped / Max
  label: string; // "8k", "16k", "Uncapped", "0.2", etc.
  isRecommended?: boolean;
}

export interface DottedIntervalSliderProps {
  label: string;
  description?: string;
  value: number;
  onChange: (val: number) => void;
  ticks: SliderTick[];
  formatDisplay?: (val: number) => string;
}

export const DottedIntervalSlider: React.FC<DottedIntervalSliderProps> = ({
  label,
  description,
  value,
  onChange,
  ticks,
  formatDisplay,
}) => {
  // Convert current value to a position 0 .. (ticks.length - 1)
  const sliderPos = useMemo(() => {
    if (value === -1) {
      // Find the uncapped tick index
      const uncappedIdx = ticks.findIndex(t => t.value === -1);
      return uncappedIdx !== -1 ? uncappedIdx : ticks.length - 1;
    }
    // Check exact match
    const exactIdx = ticks.findIndex(t => t.value === value);
    if (exactIdx !== -1) return exactIdx;

    // Between ticks: interpolate
    for (let i = 0; i < ticks.length - 1; i++) {
      const v0 = ticks[i].value;
      const v1 = ticks[i + 1].value;
      if (v1 === -1) {
        // If next is uncapped, stop interpolation at i
        return i;
      }
      if (value >= v0 && value <= v1) {
        const ratio = (value - v0) / (v1 - v0);
        return i + ratio;
      }
    }
    if (value < ticks[0].value) return 0;
    return ticks.length - 1;
  }, [value, ticks]);

  const handleSliderChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const pos = parseFloat(e.target.value);
    const i = Math.floor(pos);
    const frac = pos - i;

    if (i >= ticks.length - 1) {
      onChange(ticks[ticks.length - 1].value);
      return;
    }

    const t0 = ticks[i];
    const t1 = ticks[i + 1];

    if (t1.value === -1) {
      // Next is uncapped: snap if > 0.6 towards uncapped, else stay at t0
      if (frac > 0.6) {
        onChange(-1);
      } else {
        onChange(t0.value);
      }
      return;
    }

    if (t0.value === -1) {
      onChange(-1);
      return;
    }

    // Interpolate between numeric values
    const rawVal = t0.value + frac * (t1.value - t0.value);
    // Round nicely: if values are integers >= 1000, round to nearest 256/512/1024
    let finalVal: number;
    if (t1.value >= 1000) {
      const step = t1.value >= 10000 ? 512 : 256;
      finalVal = Math.round(rawVal / step) * step;
    } else {
      // Decimal (like temperature 0.0 - 1.0)
      finalVal = Math.round(rawVal * 100) / 100;
    }
    onChange(finalVal);
  };

  const currentDisplay = useMemo(() => {
    if (formatDisplay) return formatDisplay(value);
    if (value === -1) return 'Uncapped / Max';
    const match = ticks.find(t => t.value === value);
    if (match?.isRecommended) return `${match.label} (Recommended)`;
    return String(value);
  }, [value, ticks, formatDisplay]);

  const percent = ticks.length > 1 ? (sliderPos / (ticks.length - 1)) * 100 : 0;

  return (
    <div className="dotted-slider-card">
      <div className="dotted-slider-header">
        <div>
          <div className="dotted-slider-label">{label}</div>
          {description && <div className="dotted-slider-desc">{description}</div>}
        </div>
        <div className="dotted-slider-badge">
          {currentDisplay}
        </div>
      </div>

      <div className="dotted-slider-track-wrap">
        {/* Underlay track with dots */}
        <div className="dotted-slider-track-bg">
          <div
            className="dotted-slider-track-fill"
            style={{ width: `${percent}%` }}
          />
          {ticks.map((tick, idx) => {
            const tickPercent = (idx / (ticks.length - 1)) * 100;
            const isPassed = percent >= tickPercent - 0.5;
            const isCurrent = Math.abs(sliderPos - idx) < 0.25;

            return (
              <div
                key={`${tick.label}-${idx}`}
                className={`dotted-slider-dot ${isPassed ? 'active' : ''} ${isCurrent ? 'current' : ''} ${tick.isRecommended ? 'recommended' : ''}`}
                style={{ left: `${tickPercent}%` }}
                onClick={() => onChange(tick.value)}
                title={`${tick.label}${tick.isRecommended ? ' (Recommended)' : ''}`}
              />
            );
          })}
        </div>

        {/* Range input transparently overlaying the track */}
        <input
          type="range"
          min={0}
          max={ticks.length - 1}
          step={0.05}
          value={sliderPos}
          onChange={handleSliderChange}
          className="dotted-slider-input"
        />

        {/* Labels below dots */}
        <div className="dotted-slider-labels">
          {ticks.map((tick, idx) => {
            const tickPercent = (idx / (ticks.length - 1)) * 100;
            const isCurrent = Math.abs(sliderPos - idx) < 0.35;

            return (
              <button
                key={`lbl-${tick.label}-${idx}`}
                type="button"
                className={`dotted-slider-tick-btn ${isCurrent ? 'selected' : ''} ${tick.isRecommended ? 'recommended' : ''}`}
                style={{ left: `${tickPercent}%` }}
                onClick={() => onChange(tick.value)}
              >
                {tick.label}
                {tick.isRecommended && <span className="tick-rec-star">★</span>}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
};
