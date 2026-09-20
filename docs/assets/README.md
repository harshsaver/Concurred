# README artwork

The banner was made with the built-in image generation tool using Concurred's
[snowflake logo](../../Concurred/Assets.xcassets/AppLogo.imageset/logo.png) and the
original October WebP characters 25 (laptop/beanbag), 22 (coffee), and 31 (phone)
as visual references. It is promotional artwork.

The files in `characters/` are unmodified original WebP assets, copied from the
October artwork supplied for this app:

- `25.webp`: laptop and beanbag.
- `38.webp`: laptop.
- `43.webp`: Cloak disguise.

The chat images are unedited native app renders from
[ViewRenderingTests](../../ConcurredTests/ViewRenderingTests.swift). They use sample
conversations and mock credentials, with no live chat history or API keys.
Light and dark previews show different window sizes.

`alt-id-cloak.png` and `network-panel.png` are the user's original, unedited panel
screenshots supplied for the README. Alt ID shows Cloak on and the alternate
identity; Network shows the Chrome on Android preset. The README links each
preview to its full-size image.

## Banner prompt

```text
Use case: ads-marketing.
Asset: a finished, exceptional consumer product campaign banner for Concurred, a native Mac AI chat app. This is the hero of a GitHub README. Wide 3:1 landscape, crisp high resolution. Art direction: optimistic, confident, beautifully simple, tactile. Editorial typography and charming crafted 3D characters, with the finish of a major consumer messaging product launch.
Use these existing brand assets as references:
1. The blue snowflake app icon; keep its recognizable snowflake mark and blue color. Small near the wordmark.
2. The white soft character working on a laptop in a blue beanbag, with its coffee mug. Preserve the appealing round body, black bead eyes, prop and outfit details.
3. The white soft character holding a warm coffee mug. Same recognizably simple face and body.
4. The white soft character lying down using its phone. Preserve its pose and small pink heart chat bubble.
Design one coherent scene, not a collage of square portraits. These are the actual brand characters. Stage the three characters together across the right 55 percent on a beautifully lit pale-blue surface, the beanbag/laptop character slightly behind, the coffee character beside it, the phone character in front. Include one large sculptural cobalt-blue speech bubble behind the group and one smaller frosted white speech bubble with three dots. Use generous clear space between props and characters. A gentle contact shadow grounds them.
Background: very pale icy blue to warm white, subtle sky-blue curvature at the bottom right. Soft studio daylight, dimensional shadows, fine fabric and ceramic textures. High-end friendly product photography meets 3D illustration. Keep the palette restrained: icy blue, cobalt, white, tiny warm coffee accents. No dark space backgrounds, no neon glow, no lasers, no sparkles, no generic tech gradients or tiny clutter.
Left 45 percent: a small existing snowflake icon next to the exact wordmark "Concurred", then a huge dark navy headline with beautiful sans-serif typesetting on two or three lines. Text exactly:
"Concurred"
"Good things start with a chat."
No other text. Letterspacing and baseline precisely aligned. Keep all text legible at README width. Maintain at least 6 percent safe margin on all outer edges. Typography should feel confident and human, not futuristic. Do not put any text on top of characters. No fake app screenshot, no browser window, no platform logos, no security badges, no watermark.
This is an entirely new art direction, a bright, inviting brand world. The source characters should remain visibly recognizable.
```
