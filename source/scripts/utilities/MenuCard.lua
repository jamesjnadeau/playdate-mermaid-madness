-- MenuCard.lua
-- Shared chrome for "pick one from a list, see its description" screens: a
-- card frame (rounded rect, white background, black border) housing a fixed
-- title at top, a fixed footer at bottom, and a middle row split into a
-- scrollable left-column menu (half width, highlighting the selected item)
-- and a right-column description of that item (half width), with a divider
-- line between them. Used by UpgradeTestScene and UpgradeSelectScene's
-- "select" phase -- pulled out here since both need the identical layout
-- math and the identical playout.lua workaround (see MenuCard.build's
-- comment on the tree:layout() maxHeight cap). Also used by SettingsScene
-- (a flat list, no headers/windowing), TuningScene (which does use both
-- -- see the `headerBefore`/`opts.maxVisible` params below), and
-- EnemySelectScene (which swaps the right column's plain-text description
-- for a custom image+stats preview via `opts.buildDesc`, see below).
--
-- Three features exist purely for one caller apiece and are no-ops for every
-- other caller unless opted into:
--  - `items[i].headerBefore`: an optional non-selectable header line
--    (category name) inserted immediately before that item in the on-screen
--    list. Doesn't shift `selectedIndex`'s numbering -- that still counts
--    only selectable items, exactly like a caller with no headers at all.
--    (TuningScene only.)
--  - `opts.maxVisible`: caps how many display rows (headers + items) are
--    laid out at once, recentered around the selection on every rebuild
--    (see computeWindow below) -- the same fixed-cost-per-rebuild windowing
--    TuningScene.lua used to do itself, now shared. Omitted (the default)
--    lays out every row, which is fine for short lists (UpgradeTestScene/
--    UpgradeSelectScene/SettingsScene) but would make every keypress
--    relayout the entire list for a 90-row one. (TuningScene only.)
--  - `opts.buildDesc`: replaces the right column's default text description
--    with a custom-built image, e.g. EnemySelectScene's enemy sprite +
--    health/speed/accel/turn stats. Omitted (the default) renders
--    `items[selectedIndex].description` as centered text. (EnemySelectScene
--    only.)

---@class MenuCard
MenuCard = {}

local gfx <const> = playdate.graphics
local floor <const> = math.floor

-- Draws a sine-wave polyline from y=y0 to y=y1 along vertical baseline x, so
-- the divider reads as a little wave rather than a flat rule (matching the
-- water's look -- see GameScene:drawWavelet and GameSceneTraining's
-- drawWaveBar, which does the same thing horizontally). Static -- no phase
-- parameter -- since the divider doesn't need to move.
---@param x number
---@param y0 number
---@param y1 number
local function drawWaveLine(x, y0, y1)
	local amplitude = Config.WIND_BAR_WAVE_AMPLITUDE
	local k = 2 * math.pi / Config.WIND_BAR_WAVE_WAVELENGTH
	local segLen = 3
	local prevX, prevY = x + amplitude * math.sin(0), y0
	local y = y0
	while y < y1 - 0.001 do
		local ny = math.min(y + segLen, y1)
		local nx = x + amplitude * math.sin(ny * k)
		gfx.drawLine(prevX, prevY, nx, ny)
		prevX, prevY = nx, ny
		y = ny
	end
end

MenuCard.CARD_MARGIN = 8
MenuCard.CARD_BORDER = 0
MenuCard.CARD_RADIUS = 6
MenuCard.CARD_PADDING = 8
-- Gap between the title/footer and the menu+description row below/above them.
MenuCard.ROW_GAP = 6
-- Menu (left) vs. description (right) split of the middle row, and the
-- divider line drawn between them.
MenuCard.MENU_FRACTION = 1 / 2
MenuCard.DIVIDER_GAP = 6

---@class MenuCard.Item
---@field title string
---@field description string shown in the description pane when this item is selected
---@field headerBefore? string non-selectable header line inserted immediately before this item -- see the file header comment

---@class MenuCard.Layout
---@field titleImg _Image
---@field footerImg _Image
---@field descImg _Image
---@field listTree table playout tree for the menu
---@field listImg _Image drawn image of listTree, may be taller than its on-screen viewport once scrolled
---@field selectedRect table rect of the highlighted item within listImg

-- Centers a maxVisible-row window around displayPos within a list of
-- rowCount rows, clamped so the window never runs past either end -- same
-- idea as TuningScene.lua's old (now removed) computeScrollStart, just
-- generalized over an arbitrary maxVisible instead of a hardcoded constant.
---@param displayPos integer
---@param rowCount integer
---@param maxVisible integer
---@return integer start
---@return integer lastVisible
local function computeWindow(displayPos, rowCount, maxVisible)
	local start = displayPos - floor(maxVisible / 2)
	local maxStart = math.max(1, rowCount - maxVisible + 1)
	start = math.max(1, math.min(start, maxStart))
	return start, math.min(rowCount, start + maxVisible - 1)
end

-- Builds everything MenuCard.draw() needs to render one frame. Call again
-- (a fresh MenuCard.Layout, not a mutation of the last one) whenever the
-- selection changes.
---@param titleText string
---@param footerText string
---@param items MenuCard.Item[]
---@param selectedIndex integer
---@param font _Font? font override (see e.g. UpgradeSelectScene's MENU_FONT), or nil for the current global font
---@param opts? { maxVisible?: integer, buildDesc?: fun(item: MenuCard.Item, index: integer, descWidth: number, font: _Font?): _Image } maxVisible windows the display rows (headers + items) to that many at once, recentered on the selection every rebuild -- see the file header comment. Omitted lays out every row. buildDesc, if given, replaces the default plain-text description pane with a custom one (e.g. EnemySelectScene's enemy preview + stats) -- called with the selected item and handed the description pane's width to lay out into.
---@return MenuCard.Layout
function MenuCard.build(titleText, footerText, items, selectedIndex, font, opts)
	opts = opts or {}
	local contentWidth = Config.SCREEN_W - 2 * (MenuCard.CARD_MARGIN + MenuCard.CARD_PADDING)
	local menuWidth = floor((contentWidth - MenuCard.DIVIDER_GAP) * MenuCard.MENU_FRACTION)
	local descWidth = contentWidth - MenuCard.DIVIDER_GAP - menuWidth

	---@type MenuCard.Layout
	local layout = {}

	layout.titleImg = playout.tree.new(playout.text.new(titleText, { font = font })):draw()
	layout.footerImg = playout.tree.new(playout.text.new(footerText, { font = font })):draw()

	-- Expands `items` into on-screen display rows, inserting a header text
	-- row wherever an item declares `headerBefore`. Headers take up a
	-- display slot but never affect `selectedIndex`'s numbering, which still
	-- counts only items -- a caller with no headerBefore anywhere gets
	-- displayRows == items 1:1, same as before this feature existed.
	local displayRows = {}
	local selectedDisplayPos
	for i, item in ipairs(items) do
		if item.headerBefore then
			displayRows[#displayRows + 1] = { header = item.headerBefore }
		end
		displayRows[#displayRows + 1] = { itemIndex = i }
		if i == selectedIndex then selectedDisplayPos = #displayRows end
	end

	local startPos, lastPos = 1, #displayRows
	if opts.maxVisible then
		startPos, lastPos = computeWindow(selectedDisplayPos, #displayRows, opts.maxVisible)
	end

	local children = {}
	if opts.maxVisible and startPos > 1 then
		children[#children + 1] = playout.text.new("^ more above")
	end
	for pos = startPos, lastPos do
		local row = displayRows[pos]
		if row.header then
			children[#children + 1] = playout.text.new(row.header)
		else
			local i = row.itemIndex
			local item = items[i]
			local isSelected = i == selectedIndex
			children[#children + 1] = playout.box.new({
				id = "item" .. i,
				padding = 4,
				hAlign = playout.kAlignStart,
				backgroundColor = isSelected and gfx.kColorBlack or nil,
			}, {
				playout.text.new(item.title, {
					color = isSelected and gfx.kColorWhite or gfx.kColorBlack,
				}),
			})
		end
	end
	if opts.maxVisible and lastPos < #displayRows then
		children[#children + 1] = playout.text.new("v more below")
	end
	local listRoot = playout.box.new({
		direction = playout.kDirectionVertical,
		spacing = 4,
		padding = 4,
		border = 0,
		borderColor = 0,
		hAlign = playout.kAlignStart,
		width = menuWidth,
		maxHeight = math.huge,
		font = font,
	}, children)
	layout.listTree = playout.tree.new(listRoot)
	-- tree:draw() calls tree:layout() internally, which hardcodes a maxHeight
	-- of Config.SCREEN_H (240) -- fine for screen-sized trees, but it would
	-- silently cut off anything the root box laid out beyond that, regardless
	-- of the root's own (raised) maxHeight above. Laying out here instead,
	-- with an uncapped maxHeight, and handing tree:draw() the result via
	-- tree.rect lets the full list exist in the drawn image; MenuCard.draw()
	-- then scrolls+clips it to keep the selection visible.
	layout.listTree.rect = listRoot:layout({
		maxWidth = menuWidth,
		maxHeight = math.huge,
		path = "root",
	})
	layout.listImg = layout.listTree:draw()
	layout.selectedRect = layout.listTree:get("item" .. selectedIndex).rect

	if opts.buildDesc then
		layout.descImg = opts.buildDesc(items[selectedIndex], selectedIndex, descWidth, font)
	else
		layout.descImg = playout.tree.new(playout.box.new({
			width = descWidth,
			padding = 4,
			hAlign = playout.kAlignCenter,
			vAlign = playout.kAlignCenter,
			font = font,
		}, {
			playout.text.new(items[selectedIndex].description, { alignment = kTextAlignment.center }),
		})):draw()
	end

	return layout
end

-- Draws a MenuCard.Layout built by MenuCard.build() to the screen.
---@param layout MenuCard.Layout
function MenuCard.draw(layout)
	gfx.setImageDrawMode(gfx.kDrawModeCopy)

	local cardX, cardY = MenuCard.CARD_MARGIN, MenuCard.CARD_MARGIN
	local cardW = Config.SCREEN_W - 2 * MenuCard.CARD_MARGIN
	local cardH = Config.SCREEN_H - 2 * MenuCard.CARD_MARGIN
	gfx.setColor(gfx.kColorWhite)
	gfx.fillRoundRect(cardX, cardY, cardW, cardH, MenuCard.CARD_RADIUS)
	gfx.setColor(gfx.kColorBlack)
	-- gfx.setLineWidth(MenuCard.CARD_BORDER)
	-- gfx.drawRoundRect(cardX, cardY, cardW, cardH, MenuCard.CARD_RADIUS)

	local contentX = cardX + MenuCard.CARD_PADDING
	local contentY = cardY + MenuCard.CARD_PADDING
	local contentW = cardW - 2 * MenuCard.CARD_PADDING

	layout.titleImg:draw(contentX + (contentW - layout.titleImg.width) / 2, contentY)
	local footerY = cardY + cardH - MenuCard.CARD_PADDING - layout.footerImg.height
	layout.footerImg:draw(contentX + (contentW - layout.footerImg.width) / 2, footerY)

	local middleY = contentY + layout.titleImg.height + MenuCard.ROW_GAP
	local middleHeight = footerY - MenuCard.ROW_GAP - middleY

	local menuWidth = floor((contentW - MenuCard.DIVIDER_GAP) * MenuCard.MENU_FRACTION)
	local menuX = contentX
	local descX = contentX + menuWidth + MenuCard.DIVIDER_GAP
	local descWidth = contentW - MenuCard.DIVIDER_GAP - menuWidth

	local dividerX = menuX + menuWidth + MenuCard.DIVIDER_GAP / 2
	gfx.setColor(gfx.kColorBlack)
	gfx.setLineWidth(1)
	drawWaveLine(dividerX, middleY, middleY + middleHeight)

	local listY
	if layout.listImg.height <= middleHeight then
		listY = middleY + (middleHeight - layout.listImg.height) / 2
	else
		-- List is taller than its viewport -- scroll it vertically so the
		-- highlighted item stays centered, clamped so we never scroll past
		-- the top (listY > middleY) or bottom
		-- (listY < middleY + middleHeight - listImg.height) edge.
		local selectedCenterY = layout.selectedRect.y + layout.selectedRect.height / 2
		listY = middleY + middleHeight / 2 - selectedCenterY
		listY = math.max(middleY + middleHeight - layout.listImg.height, math.min(middleY, listY))
	end

	gfx.setClipRect(menuX, middleY, menuWidth, middleHeight)
	layout.listImg:draw(menuX, listY)
	gfx.clearClipRect()

	layout.descImg:draw(descX + (descWidth - layout.descImg.width) / 2, middleY + (middleHeight - layout.descImg.height) / 2)
end
