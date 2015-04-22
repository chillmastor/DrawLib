--- TODO
--
--- Test other Vector3 interpolation methods
--- Fix WorldLocToScreenPoint outside-of-screen bugging
--- Allow re-interpolation of curved path with fewer points based on distance to player
--- Make a proper Path object
---
--- Player unit gets recreated on zone transition, this breaks TrackUnit

DrawLib = {
	name = "DrawLib",
	version = "0.0.10",

	tCircle = {},
	tPaths = {},
	tTrackedUnits = {},
	
	tStyle = {
		nLineWidth = 3,
		crLineColor = ApolloColor.new(0/255, 160/255,  200/255):ToTable(),
		bOutline = true,
	},
}

local cos = math.cos
local sin = math.sin

local function deepcopy(orig)
    if type(orig) ~= 'table' then return orig else
        local copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
		return copy
    end
end

--

function DrawLib:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("DrawLib.xml")
	self.wndOverlay = Apollo.LoadForm(self.xmlDoc, "Overlay", "InWorldHudStratum", self)
	Apollo.RegisterEventHandler("UnitCreated", "OnUnitCreated", self)
	Apollo.RegisterEventHandler("NextFrame", "OnFrame", self)
end

-- API

function DrawLib:TrackUnit(tUnit, tStyle, tPath)
	if not tPath then -- default path: player to unit line
		tPath = {type = "path", tVertices = {{unit = GameLib.GetPlayerUnit()}, {}}}
	end
	tPath.tStyle = tStyle or self.tStyle
	self.tTrackedUnits[tUnit] = tPath
end

function DrawLib:UnitLine(unitSrc, unitDst, param)
	if unitSrc and unitSrc:IsValid() then
		if unitDst and unitDst:IsValid() then
			
			if type(param) == 'string' then
				tStyle = {
					nLineWidth = 3,
					crLineColor = param,
					bOutline = true,
				}
			end
			
			local tPath = {type = "unitline", unitSrc = unitSrc, unitDst = unitDst, tStyle = tStyle or self.tStyle}
			self.tPaths[#self.tPaths+1] = tPath
			return tPath
		else
		 	Print("DrawLib: Invalid destination unit in DrawLib:UnitLine()")
		end
	else
		Print("DrawLib: Invalid source unit in DrawLib:UnitLine()")
	end
end

function DrawLib:UnitText(unit, text)
	if unit and unit:IsValid() then
		local wndMark = Apollo.LoadForm(self.xmlDoc, "unitMark", "FixedHudStratumHigh", self)
		wndMark:FindChild("Text"):SetText(text)
		local tPath = { type = "unit", unit = unit, wndMark = wndMark }
		self.tPaths[#self.tPaths+1] = tPath
		return tPath
	else
		Print("DrawLib: Invalid unit in DrawLib:UnitText()")
	end
end

function DrawLib:Path(tVectors, tStyle)
	local tPath = {type = "path", tVectors = tVectors, tStyle = tStyle or self.tStyle}
	self.tPaths[#self.tPaths+1] = tPath
	return tPath
end

function DrawLib:Destroy(tPath)
	for i=#self.tPaths,1,-1 do
		if self.tPaths[i] == tPath then
			if tPath.wndMark then 
				tPath.wndMark:Destroy()
				tPath.wndMark = nil
			end
			table.remove(self.tPaths,i)
		end
	end
end

--

function DrawLib:OnUnitCreated(unit)
	for tUnit, tPath in pairs(self.tTrackedUnits) do
		if ((not tUnit.strName) or tUnit.strName == unit:GetName()) then -- BUG: what if tUnit is empty or not a table
			tPath.unit = unit
			self.tPaths[#self.tPaths+1] = deepcopy(tPath)
		end
	end
end

-- Draw Handlers

function DrawLib:OnFrame()
	self.wndOverlay:DestroyAllPixies()
	for i=#self.tPaths,1,-1 do
		local tPath = self.tPaths[i]
		if tPath then
			if tPath.type == "unitline" then
				if tPath.unitSrc:IsValid() and tPath.unitDst:IsValid() then
					local pSrc = GameLib.WorldLocToScreenPoint(Vector3.New(tPath.unitSrc:GetPosition()))
					local pDst = GameLib.WorldLocToScreenPoint(Vector3.New(tPath.unitDst:GetPosition()))
					self:DrawLine(pSrc, pDst, tPath.tStyle)
				else
					table.remove(self.tPaths,i)
				end
			elseif tPath.type == "unit" then
				if tPath.unit:IsValid() then
					tPath.wndMark:SetUnit(tPath.unit)
				else
					tPath.wndMark:Destroy()
					table.remove(self.tPaths,i)
				end
			elseif tPath.type == "path" then
				self:DrawPath(tPath)
			end
		end
	end
end

function DrawLib:DrawPath(tPath)
	local tScreenPoints = {}
	local vPathOffset = tPath.vOffset or Vector3.New(0,0,0)
	
	if tPath.unit then
		if tPath.unit:IsValid() then
			vPathOffset = vPathOffset + Vector3.New(tPath.unit:GetPosition())
		else
			self:Destroy(tPath)
			return
		end
	end
	
	for i=1,#tPath.tVertices do
		local vPoint
		tVertex = tPath.tVertices[i]
		if tVertex.unit then
			if tVertex.unit:IsValid() then
				vPoint = Vector3.New(tVertex.unit:GetPosition())
			else
				self:Destroy(tPath)
				return
			end
		else 
			vPoint = tVertex.vPos or Vector3.New(0,0,0)
			vPoint = vPoint + vPathOffset
			if tVertex.vOffset then vPoint = vPoint + tVertex.vOffset end
		end
		tScreenPoints[i] = GameLib.WorldLocToScreenPoint(vPoint)
	end
	
	if tPath.bClosed then tScreenPoints[#tScreenPoints+1] = tScreenPoints[1] end
	
	for i=1,#tScreenPoints-1 do
		self:DrawLine(tScreenPoints[i], tScreenPoints[i+1], tPath.tStyle)
	 end
end

function DrawLib:DrawLine(pA, pB, tStyle)
	local tLine = {bLine = true, loc = { nOffsets = { pA.x, pA.y, pB.x, pB.y } } }
	if tStyle.bOutline then
		tLine.fWidth = tStyle.nLineWidth + 2
		tLine.cr = "black"
		self.wndOverlay:AddPixie(tLine)
	end
	tLine.fWidth = tStyle.nLineWidth
	tLine.cr = tStyle.crLineColor
	self.wndOverlay:AddPixie(tLine)
end

function DrawLib:CalcCircleVectors(nSides, fOffset)
	local tVectors = {}
	for i=0,nSides-1 do
		local angle = 2*i*math.pi/nSides + (fOffset or 0)
		tVectors[i+1] = Vector3.New(-sin(angle), 0, -cos(angle))
	end
	return tVectors
end

function DrawLib:DrawCircle(vPos, fRadius, nSides, tStyle)
	-- Cache circle vectors
	self.tCircle[nSides] = self.tCircle[nSides] or self:CalcCircleVectors(nSides)	
	local tVectors = {}
	for i=1,#self.tCircle[nSides] do tVectors[i] = vPos + self.tCircle[nSides][i]*fRadius end
	self:DrawPath({tVectors = tVectors, bClosed = true, tStyle = tStyle})
end

function DrawLib:DrawUnitCircle(unit, fRadius, nSides, tStyle)
	-- Cache circle vectors
	self.tCircle[nSides] = self.tCircle[nSides] or self:CalcCircleVectors(nSides)
	
	local tPath = {tVertices = {}, unit = unit, bClosed = true, tStyle = tStyle}

	for i=1,#self.tCircle[nSides] do tPath.tVertices[i] = {vPos = self.tCircle[nSides][i]*fRadius} end 
	self:DrawPath(tPath)
end

-- Leftover stuff

function DrawLib:CurvePath(tPath) -- native catmull-rom with 10 segments
	local tCurvedPath = {}
	for i=0,#tPath-2 do
		local vA = (i>0) and tPath[i] or tPath[i+1]
		local vB = tPath[i+1]
		local vC = tPath[i+2]
		local vD = (i<#tPath-2) and tPath[i+3] or tPath[i+2]
		for j=1,10 do tCurvedPath[10*i+j] = Vector3.InterpolateCatmullRom(vA,vB,vC,vD,j/10)	end
	end
	return tCurvedPath
end

function DrawLib:GetSqDistanceToSeg(vP,vA,vB)
	local vC = vA
	if vA ~= vB then 
		local vDir = vB - vA
		local fSqLen = vDir:LengthSq()
		local t = Vector3.Dot(vDir, vP - vA) / fSqLen
		if t > 1 then vC = vB elseif t > 0 then vC = vA + vDir*t end
	end
	return (vP-vC):LengthSq()
end

function DrawLib:SimplifyPath(tPath, fTolerance) -- Ramer-Douglas-Peucker 
	local tSimplePath = {}
	local tMarkers = {[1] = true, [#tPath] = true}
	local index

	local tStack = {#tPath, 1}
	
	while #tStack > 0 do
	
		local maxDist = 0
	
		local first = tStack[#tStack]
		tStack[#tStack] = nil
		local last = tStack[#tStack]
		tStack[#tStack] = nil
	
		for i=first+1,last-1 do
			local SqDist = self:GetSqDistanceToSeg(tPath[i],tPath[first],tPath[last])
			if SqDist > maxDist then
				maxDist = SqDist
				index = i
			end
		end
		
		if maxDist > fTolerance then
			tMarkers[index] = true
			tStack[#tStack+1] = last
			tStack[#tStack+1] = index
			tStack[#tStack+1] = index
			tStack[#tStack+1] = first
		end
		
	end
	
	for i=1,#tPath do
		if tMarkers[i] then
			tSimplePath[#tSimplePath+1] = tPath[i]
		end
	end
	
	return tSimplePath
end

Apollo.RegisterAddon(DrawLib)