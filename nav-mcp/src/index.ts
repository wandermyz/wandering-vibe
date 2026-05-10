#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

function expandPath(p: string): string {
  if (p === "~") return homedir();
  if (p.startsWith("~/")) return homedir() + p.slice(1);
  return p;
}

function loadApiKey(): string | undefined {
  const inline = process.env.GOOGLE_MAPS_API_KEY?.trim();
  if (inline) return inline;
  const rawPath = process.env.GOOGLE_MAPS_API_KEY_FILE?.trim();
  if (!rawPath) return undefined;
  const path = expandPath(rawPath);
  try {
    return readFileSync(path, "utf8").trim();
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(
      `nav-mcp: could not read GOOGLE_MAPS_API_KEY_FILE (${path}): ${msg}\n`
    );
    return undefined;
  }
}

const ROUTES_ENDPOINT =
  "https://routes.googleapis.com/directions/v2:computeRoutes";

const TRAVEL_MODES = [
  "DRIVE",
  "BICYCLE",
  "WALK",
  "TWO_WHEELER",
  "TRANSIT",
] as const;

const ROUTING_PREFERENCES = [
  "TRAFFIC_AWARE",
  "TRAFFIC_AWARE_OPTIMAL",
  "TRAFFIC_UNAWARE",
] as const;

const DriveTimeInput = z.object({
  origin: z
    .string()
    .min(1)
    .describe(
      "Origin location: a street address, place name, or 'lat,lng' pair (e.g. '37.7749,-122.4194')."
    ),
  destination: z
    .string()
    .min(1)
    .describe("Destination location, same format as origin."),
  waypoints: z
    .array(z.string().min(1))
    .optional()
    .describe(
      "Optional ordered intermediate stops between origin and destination. Same format as origin (address, place name, or 'lat,lng'). Up to 25."
    ),
  optimize_waypoint_order: z
    .boolean()
    .optional()
    .default(false)
    .describe(
      "If true, Google reorders waypoints to minimize total travel time. The output reflects the optimized order."
    ),
  include_steps: z
    .boolean()
    .optional()
    .default(false)
    .describe(
      "If true, include turn-by-turn navigation instructions in the response. Defaults to false to keep output short."
    ),
  travel_mode: z
    .enum(TRAVEL_MODES)
    .optional()
    .default("DRIVE")
    .describe("Travel mode. Defaults to DRIVE."),
  routing_preference: z
    .enum(ROUTING_PREFERENCES)
    .optional()
    .default("TRAFFIC_AWARE")
    .describe(
      "Driving routing preference. Ignored for non-DRIVE modes. Defaults to TRAFFIC_AWARE (live traffic)."
    ),
  departure_time: z
    .string()
    .datetime()
    .optional()
    .describe(
      "ISO-8601 future timestamp for departure (e.g. '2026-05-10T18:00:00Z'). Defaults to now."
    ),
  units: z
    .enum(["METRIC", "IMPERIAL"])
    .optional()
    .default("IMPERIAL")
    .describe("Distance units in the response. Defaults to IMPERIAL."),
});

type DriveTimeInputT = z.infer<typeof DriveTimeInput>;

const LATLNG_RE = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/;

function buildWaypoint(s: string): Record<string, unknown> {
  const m = s.match(LATLNG_RE);
  if (m) {
    return {
      location: {
        latLng: { latitude: Number(m[1]), longitude: Number(m[2]) },
      },
    };
  }
  return { address: s };
}

function formatDuration(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return `${seconds}s`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h === 0) return `${m} min`;
  return `${h} hr ${m} min`;
}

function formatDistance(meters: number, units: "METRIC" | "IMPERIAL"): string {
  if (units === "IMPERIAL") {
    const miles = meters / 1609.344;
    return `${miles.toFixed(miles >= 10 ? 0 : 1)} mi`;
  }
  if (meters >= 1000) return `${(meters / 1000).toFixed(meters >= 10000 ? 0 : 1)} km`;
  return `${Math.round(meters)} m`;
}

function parseDurationField(d: unknown): number {
  // Routes API returns durations as e.g. "1234s"
  if (typeof d === "string" && d.endsWith("s")) {
    const n = Number(d.slice(0, -1));
    if (Number.isFinite(n)) return n;
  }
  if (typeof d === "number") return d;
  return NaN;
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
}

async function computeDriveTime(
  apiKey: string,
  input: DriveTimeInputT
): Promise<string> {
  const waypoints = input.waypoints ?? [];
  const body: Record<string, unknown> = {
    origin: buildWaypoint(input.origin),
    destination: buildWaypoint(input.destination),
    travelMode: input.travel_mode,
    units: input.units,
  };

  if (waypoints.length > 0) {
    body.intermediates = waypoints.map(buildWaypoint);
    if (input.optimize_waypoint_order) {
      body.optimizeWaypointOrder = true;
    }
  }

  if (input.travel_mode === "DRIVE" || input.travel_mode === "TWO_WHEELER") {
    body.routingPreference = input.routing_preference;
  }
  if (input.departure_time) {
    body.departureTime = input.departure_time;
  }

  const fieldMaskParts = [
    "routes.duration",
    "routes.staticDuration",
    "routes.distanceMeters",
    "routes.description",
    "routes.warnings",
    "routes.optimizedIntermediateWaypointIndex",
    "routes.legs.duration",
    "routes.legs.staticDuration",
    "routes.legs.distanceMeters",
    "routes.legs.startLocation",
    "routes.legs.endLocation",
  ];
  if (input.include_steps) {
    fieldMaskParts.push(
      "routes.legs.steps.navigationInstruction",
      "routes.legs.steps.distanceMeters",
      "routes.legs.steps.staticDuration"
    );
  }
  const fieldMask = fieldMaskParts.join(",");

  const res = await fetch(ROUTES_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": fieldMask,
    },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  if (!res.ok) {
    throw new Error(
      `Google Routes API error ${res.status} ${res.statusText}: ${text}`
    );
  }

  let parsed: any;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`Could not parse Routes API response: ${text}`);
  }

  const route = parsed?.routes?.[0];
  if (!route) {
    throw new Error(
      `No route found between "${input.origin}" and "${input.destination}".`
    );
  }

  const trafficSec = parseDurationField(route.duration);
  const staticSec = parseDurationField(route.staticDuration);
  const meters: number = route.distanceMeters ?? 0;

  const orderedStops = (() => {
    if (waypoints.length === 0) return [input.origin, input.destination];
    const idxs: number[] | undefined = route.optimizedIntermediateWaypointIndex;
    const orderedWaypoints =
      input.optimize_waypoint_order && Array.isArray(idxs)
        ? idxs.map((i) => waypoints[i])
        : waypoints;
    return [input.origin, ...orderedWaypoints, input.destination];
  })();

  const lines: string[] = [];
  if (waypoints.length === 0) {
    lines.push(
      `From: ${input.origin}\nTo:   ${input.destination}\nMode: ${input.travel_mode}`
    );
  } else {
    lines.push(`Mode: ${input.travel_mode}`);
    lines.push("Stops:");
    orderedStops.forEach((s, i) => {
      const tag = i === 0 ? "start" : i === orderedStops.length - 1 ? "end" : `stop ${i}`;
      lines.push(`  ${i + 1}. ${s}  (${tag})`);
    });
    if (input.optimize_waypoint_order) lines.push("(waypoint order optimized)");
  }
  if (input.departure_time) lines.push(`Depart: ${input.departure_time}`);
  lines.push("");
  lines.push("Total");
  if (Number.isFinite(trafficSec)) {
    lines.push(`  Duration (with traffic): ${formatDuration(trafficSec)}`);
  }
  if (Number.isFinite(staticSec) && staticSec !== trafficSec) {
    lines.push(`  Duration (free flow):    ${formatDuration(staticSec)}`);
  }
  lines.push(`  Distance: ${formatDistance(meters, input.units)}`);
  if (route.description) lines.push(`  Route: ${route.description}`);
  if (Array.isArray(route.warnings) && route.warnings.length) {
    lines.push(`  Warnings: ${route.warnings.join("; ")}`);
  }

  const legs: any[] = Array.isArray(route.legs) ? route.legs : [];
  const showLegs = legs.length > 1 || input.include_steps;
  if (showLegs) {
    legs.forEach((leg, i) => {
      const from = orderedStops[i] ?? `Stop ${i + 1}`;
      const to = orderedStops[i + 1] ?? `Stop ${i + 2}`;
      const legTraffic = parseDurationField(leg.duration);
      const legStatic = parseDurationField(leg.staticDuration);
      const legMeters: number = leg.distanceMeters ?? 0;
      lines.push("");
      lines.push(`Leg ${i + 1}: ${from} → ${to}`);
      if (Number.isFinite(legTraffic)) {
        lines.push(`  Duration (with traffic): ${formatDuration(legTraffic)}`);
      }
      if (Number.isFinite(legStatic) && legStatic !== legTraffic) {
        lines.push(`  Duration (free flow):    ${formatDuration(legStatic)}`);
      }
      lines.push(`  Distance: ${formatDistance(legMeters, input.units)}`);

      if (input.include_steps && Array.isArray(leg.steps)) {
        lines.push("  Steps:");
        leg.steps.forEach((step: any, j: number) => {
          const instr =
            stripHtml(step?.navigationInstruction?.instructions ?? "") ||
            (step?.navigationInstruction?.maneuver ?? "Continue");
          const stepMeters: number = step.distanceMeters ?? 0;
          const distStr = stepMeters > 0 ? ` (${formatDistance(stepMeters, input.units)})` : "";
          lines.push(`    ${j + 1}. ${instr}${distStr}`);
        });
      }
    });
  }

  return lines.join("\n");
}

async function main() {
  const apiKey = loadApiKey();
  if (!apiKey) {
    process.stderr.write(
      "nav-mcp: no API key found. Set GOOGLE_MAPS_API_KEY (inline) or " +
        "GOOGLE_MAPS_API_KEY_FILE (path to a file containing the key). " +
        "Get a key from Google Cloud Console with the Routes API enabled.\n"
    );
    process.exit(1);
  }

  const server = new Server(
    { name: "nav-mcp", version: "0.1.0" },
    { capabilities: { tools: {} } }
  );

  server.setRequestHandler(ListToolsRequestSchema, async () => ({
    tools: [
      {
        name: "drive_time",
        description:
          "Compute travel time and distance using Google Routes API. " +
          "Supports optional intermediate stops (waypoints) and turn-by-turn directions. " +
          "Defaults to driving with live traffic. Accepts addresses, place names, or 'lat,lng' coordinates.",
        inputSchema: {
          type: "object",
          properties: {
            origin: {
              type: "string",
              description:
                "Origin: address, place name, or 'lat,lng' (e.g. '37.7749,-122.4194').",
            },
            destination: {
              type: "string",
              description: "Destination, same format as origin.",
            },
            waypoints: {
              type: "array",
              items: { type: "string" },
              description:
                "Optional ordered intermediate stops between origin and destination. Same format as origin. Up to 25.",
            },
            optimize_waypoint_order: {
              type: "boolean",
              description:
                "If true, Google reorders waypoints to minimize travel time. Output reflects the optimized order. Defaults to false.",
            },
            include_steps: {
              type: "boolean",
              description:
                "If true, include turn-by-turn navigation instructions. Defaults to false to keep output short.",
            },
            travel_mode: {
              type: "string",
              enum: [...TRAVEL_MODES],
              description: "Travel mode. Defaults to DRIVE.",
            },
            routing_preference: {
              type: "string",
              enum: [...ROUTING_PREFERENCES],
              description:
                "Routing preference for DRIVE/TWO_WHEELER. Defaults to TRAFFIC_AWARE.",
            },
            departure_time: {
              type: "string",
              description:
                "ISO-8601 future timestamp for departure. Defaults to now.",
            },
            units: {
              type: "string",
              enum: ["METRIC", "IMPERIAL"],
              description: "Distance units. Defaults to IMPERIAL.",
            },
          },
          required: ["origin", "destination"],
        },
      },
    ],
  }));

  server.setRequestHandler(CallToolRequestSchema, async (req) => {
    if (req.params.name !== "drive_time") {
      throw new Error(`Unknown tool: ${req.params.name}`);
    }
    const input = DriveTimeInput.parse(req.params.arguments ?? {});
    try {
      const out = await computeDriveTime(apiKey, input);
      return { content: [{ type: "text", text: out }] };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      return {
        isError: true,
        content: [{ type: "text", text: msg }],
      };
    }
  });

  const transport = new StdioServerTransport();
  await server.connect(transport);
  process.stderr.write("nav-mcp: ready on stdio\n");
}

main().catch((err) => {
  process.stderr.write(`nav-mcp fatal: ${err?.stack ?? err}\n`);
  process.exit(1);
});
