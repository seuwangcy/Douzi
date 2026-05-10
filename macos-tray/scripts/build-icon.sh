#!/bin/bash
set -e

# ==========================================
# Douzi Icon Builder
# 从 Assets/ 中的原始设计稿生成 macOS 所需的全部图标资源
#
# 用法:
#   ./macos-tray/scripts/build-icon.sh                  # 从已有的 final 文件生成 icns + menubar 资源
#   ./macos-tray/scripts/build-icon.sh --from-source     # 从原图重新生成全部资源
#
# 裁剪参数可通过环境变量覆盖 (应用于 AppIcon 和 menubar 图标):
#   CROP_TOP=250 CROP_LEFT=375 CROP_RIGHT=375 CROP_BOTTOM=500 \
#     ./macos-tray/scripts/build-icon.sh --from-source
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../Assets"
RESOURCES_DIR="$SCRIPT_DIR/../Resources"

SOURCE_ICON="$ASSETS_DIR/AppIcon.png"
FINAL_ICON="$ASSETS_DIR/AppIcon_final.png"
ICNS_OUTPUT="$RESOURCES_DIR/AppIcon.icns"

MENUBAR_SOURCE="$ASSETS_DIR/AppIcon_menubar.png"
MENUBAR_RESOURCES="$SCRIPT_DIR/../Sources/DouziMenuBar/Resources"

# ---- macOS Icon Specifications ----
# Source: Apple HIG + system icon measurements (Calculator, Chess, etc.)
CANVAS=1024          # macOS standard canvas size
MARGIN=100           # ~10% transparent margin per side (measured ~9.8% on system icons)
CONTENT=$((CANVAS - 2 * MARGIN))        # = 824px
RADIUS=184           # squircle corner radius ≈ 22.37% of content width

# ---- Default crop parameters (tune these per design) ----
CROP_TOP=${CROP_TOP:-250}
CROP_LEFT=${CROP_LEFT:-375}
CROP_RIGHT=${CROP_RIGHT:-375}
CROP_BOTTOM=${CROP_BOTTOM:-500}

# Parse arguments
FROM_SOURCE=false
for arg in "$@"; do
    case "$arg" in
        --from-source) FROM_SOURCE=true ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --from-source   从原图 (AppIcon.png) 重新生成 AppIcon_final.png + icns"
            echo "  --help          显示帮助"
            echo ""
            echo "裁剪参数可通过环境变量覆盖:"
            echo "  CROP_TOP=250 CROP_LEFT=375 CROP_RIGHT=375 CROP_BOTTOM=500 $0 --from-source"
            exit 0
            ;;
    esac
done

# Check dependencies
if ! command -v magick &> /dev/null; then
    echo -e "${RED}❌  ImageMagick not found. Install: brew install imagemagick${NC}"
    exit 1
fi

# ---- Step 1: Generate AppIcon_final.png from source (optional) ----
if [ "$FROM_SOURCE" = true ]; then
    if [ ! -f "$SOURCE_ICON" ]; then
        echo -e "${RED}❌  Source icon not found: $SOURCE_ICON${NC}"
        exit 1
    fi

    SRC_W=$(magick "$SOURCE_ICON" -format "%w" info:)
    SRC_H=$(magick "$SOURCE_ICON" -format "%h" info:)
    CROP_W=$((SRC_W - CROP_LEFT - CROP_RIGHT))
    CROP_H=$((SRC_H - CROP_TOP - CROP_BOTTOM))

    echo -e "${BLUE}🎨  Generating AppIcon_final.png from source...${NC}"
    echo "    Source: ${SRC_W}x${SRC_H}"
    echo "    Crop: top=${CROP_TOP} left=${CROP_LEFT} right=${CROP_RIGHT} bottom=${CROP_BOTTOM}"
    echo "    Cropped: ${CROP_W}x${CROP_H} → Content: ${CONTENT}x${CONTENT} → Canvas: ${CANVAS}x${CANVAS}"
    echo "    Margin: ${MARGIN}px (~10%), Corner radius: ${RADIUS}px"

    TMPDIR_APP=$(mktemp -d)

    # Step 1a: Crop
    magick "$SOURCE_ICON" \
        -crop ${CROP_W}x${CROP_H}+${CROP_LEFT}+${CROP_TOP} +repage \
        "$TMPDIR_APP/cropped.png"

    # Step 1b: Resize to content area
    magick "$TMPDIR_APP/cropped.png" -resize ${CONTENT}x${CONTENT}! "$TMPDIR_APP/resized.png"

    # Step 1c: Create rounded rect mask
    magick -size ${CONTENT}x${CONTENT} xc:none \
        -draw "roundrectangle 0,0 $((CONTENT-1)),$((CONTENT-1)) ${RADIUS},${RADIUS}" \
        "$TMPDIR_APP/mask.png"

    # Step 1d: Apply mask
    magick "$TMPDIR_APP/resized.png" "$TMPDIR_APP/mask.png" \
        -compose DstIn -composite "$TMPDIR_APP/masked.png"

    # Step 1e: Place on canvas with transparent margin
    magick -size ${CANVAS}x${CANVAS} xc:none "$TMPDIR_APP/masked.png" \
        -gravity center -composite "$FINAL_ICON"

    rm -rf "$TMPDIR_APP"

    echo -e "${GREEN}✅  Generated: $FINAL_ICON${NC}"
fi

# ---- Step 2: Generate .icns from AppIcon_final.png ----
if [ ! -f "$FINAL_ICON" ]; then
    echo -e "${RED}❌  AppIcon_final.png not found: $FINAL_ICON${NC}"
    echo "    Run with --from-source to generate it first."
    exit 1
fi

echo -e "${BLUE}📦  Generating AppIcon.icns...${NC}"
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

for size in 16 32 128 256 512; do
    magick "$FINAL_ICON" -resize ${size}x${size} "$ICONSET_DIR/icon_${size}x${size}.png"
    magick "$FINAL_ICON" -resize $((size*2))x$((size*2)) "$ICONSET_DIR/icon_${size}x${size}@2x.png"
done

mkdir -p "$RESOURCES_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_OUTPUT"
rm -rf "$(dirname "$ICONSET_DIR")"

echo -e "${GREEN}✅  Generated: $ICNS_OUTPUT${NC}"

# ================================================================
# Part 2: Menu Bar Icon
# ================================================================
# macOS menu bar icon specs:
#   - Size: 18x18pt (@1x = 18x18px, @2x = 36x36px)
#   - Light mode: black icon on transparent background
#   - Dark mode: white icon on transparent background
#   - Source image: pure black artwork on white/opaque background
#   - Processing: crop → remove white bg → scale → generate dark variant

if [ "$FROM_SOURCE" = true ] && [ -f "$MENUBAR_SOURCE" ]; then
    echo ""
    echo -e "${BLUE}🖥️   Generating menu bar icons from source...${NC}"

    # Step 1: Crop with same parameters as AppIcon
    MB_SRC_W=$(magick "$MENUBAR_SOURCE" -format "%w" info:)
    MB_SRC_H=$(magick "$MENUBAR_SOURCE" -format "%h" info:)
    MB_CROP_W=$((MB_SRC_W - CROP_LEFT - CROP_RIGHT))
    MB_CROP_H=$((MB_SRC_H - CROP_TOP - CROP_BOTTOM))

    TMPDIR_MB=$(mktemp -d)

    echo "    Crop: ${MB_SRC_W}x${MB_SRC_H} → ${MB_CROP_W}x${MB_CROP_H}"
    magick "$MENUBAR_SOURCE" \
        -crop ${MB_CROP_W}x${MB_CROP_H}+${CROP_LEFT}+${CROP_TOP} +repage \
        "$TMPDIR_MB/cropped.png"

    # Step 2: Remove white background (luminance → alpha, fill RGB black)
    # This creates a template image: black artwork + alpha channel
    # macOS will automatically colorize it for light/dark mode via isTemplate=true
    echo "    Removing white background (creating template image)..."
    magick "$TMPDIR_MB/cropped.png" \
        -colorspace Gray -negate -alpha copy \
        -channel RGB -evaluate set 0 +channel \
        "$TMPDIR_MB/template_raw.png"

    # Step 3: Resize to @1x (18x18) and @2x (36x36)
    echo "    Generating 1x/2x variants..."
    magick "$TMPDIR_MB/template_raw.png" -resize 36x36 "$MENUBAR_RESOURCES/AppIcon_menubar@2x.png"
    magick "$TMPDIR_MB/template_raw.png" -resize 18x18 "$MENUBAR_RESOURCES/AppIcon_menubar.png"

    rm -rf "$TMPDIR_MB"

    echo -e "${GREEN}✅  Menu bar template icons generated:${NC}"
    echo "    AppIcon_menubar.png (18x18), AppIcon_menubar@2x.png (36x36)"
    echo "    (isTemplate=true in code; macOS handles light/dark automatically)"
elif [ "$FROM_SOURCE" = true ] && [ ! -f "$MENUBAR_SOURCE" ]; then
    echo -e "${YELLOW}⚠️  Menu bar source not found: $MENUBAR_SOURCE, skipping.${NC}"
fi

echo ""
echo -e "${GREEN}Done! 提交更新后的资源文件，用户通过 douzi update 即可生效。${NC}"