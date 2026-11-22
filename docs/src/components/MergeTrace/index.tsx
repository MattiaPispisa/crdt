import { useState, type CSSProperties, type ReactNode } from "react";
import clsx from "clsx";

import { useTrace } from "../Recipe/data";
import type { Trace, TraceStep, TraceToken } from "../../../plugins/recipes/types";
import styles from "./styles.module.css";

/** The color of the peer at [index] in the trace: it follows the peer. */
function peerColor(index: number): string {
  return `var(--merge-trace-peer-${index + 1})`;
}

function colorStyle(trace: Trace, peer: string | null): CSSProperties {
  const index = peer === null ? -1 : trace.peers.indexOf(peer);
  return index < 0 ? {} : ({ "--peer": peerColor(index) } as CSSProperties);
}

function Value({
  trace,
  tokens,
}: {
  trace: Trace;
  tokens: TraceToken[];
}): ReactNode {
  if (tokens.length === 0) {
    return <span className={styles.empty}>empty</span>;
  }
  if (trace.kind === "text") {
    return (
      <code className={styles.text}>
        {tokens.map((token, index) => (
          <span
            key={index}
            className={clsx(token.author !== null && styles.authored)}
            style={colorStyle(trace, token.author)}
            title={token.author === null ? undefined : `written by ${token.author}`}
          >
            {token.text}
          </span>
        ))}
      </code>
    );
  }
  const Items = trace.kind === "list" ? "ol" : "ul";
  return (
    <Items className={clsx(styles.items, trace.kind === "set" && styles.set)}>
      {tokens.map((token, index) => (
        <li key={index}>{token.text}</li>
      ))}
    </Items>
  );
}

function Peer({
  trace,
  step,
  peer,
}: {
  trace: Trace;
  step: TraceStep;
  peer: string;
}): ReactNode {
  const received = step.received?.[peer] ?? [];
  return (
    <div
      className={clsx(styles.peer, step.actor === peer && styles.acting)}
      style={colorStyle(trace, peer)}
    >
      <div className={styles.peerHeader}>
        <span className={styles.swatch} aria-hidden />
        <strong>{peer}</strong>
        <span className={clsx(styles.status, !step.online && styles.offline)}>
          {step.online ? "online" : "offline"}
        </span>
      </div>
      <Value trace={trace} tokens={step.values[peer]} />
      {step.actor === peer && step.label && (
        <p className={styles.edit}>✎ {step.label}</p>
      )}
      {received.map((edit) => (
        <p key={edit.label} className={styles.received}>
          ← {edit.label} <span className={styles.from}>from {edit.from}</span>
          {edit.concurrent && <span className={styles.tag}>concurrent</span>}
        </p>
      ))}
    </div>
  );
}

/**
 * A merge, step by step: what each peer reads after each edit and sync. The
 * steps come from a test that runs the scenario on real documents.
 */
export default function MergeTrace({ id }: { id: string }): ReactNode {
  const trace = useTrace(id);
  const [index, setIndex] = useState(0);
  const step = trace.steps[index];
  const last = trace.steps.length - 1;

  return (
    <figure className={styles.trace}>
      <div className={styles.peers}>
        {trace.peers.map((peer) => (
          <Peer key={peer} trace={trace} step={step} peer={peer} />
        ))}
      </div>
      <figcaption className={styles.caption} aria-live="polite">
        <span className={styles.counter}>
          Step {index + 1} of {trace.steps.length}
        </span>
        {step.caption}
      </figcaption>
      {step.why && (
        <p className={styles.why}>
          <strong>Why: </strong>
          {step.why}
        </p>
      )}
      <div className={styles.controls}>
        <button
          type="button"
          className="button button--sm button--secondary"
          onClick={() => setIndex(index - 1)}
          disabled={index === 0}
        >
          ← Back
        </button>
        <div className={styles.dots}>
          {trace.steps.map((candidate, at) => (
            <button
              key={at}
              type="button"
              className={clsx(styles.dot, at === index && styles.current)}
              onClick={() => setIndex(at)}
              aria-label={`Step ${at + 1}: ${candidate.caption}`}
              aria-current={at === index ? "step" : undefined}
            />
          ))}
        </div>
        <button
          type="button"
          className="button button--sm button--primary"
          onClick={() => setIndex(index + 1)}
          disabled={index === last}
        >
          Next →
        </button>
      </div>
    </figure>
  );
}
