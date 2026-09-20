document.addEventListener('DOMContentLoaded', () => {
    // API & Data State
    const MAPS_API = 'https://maps-metadata.beyondallreason.dev/latest/lobby_maps.validated.json';
    let mapsData = [];
    let currentMap = null;

    // Viewport & Scale State
    let imageNaturalRatio = 1;
    let overlayRect = { width: 0, height: 0, left: 0, top: 0 };

    // Overlay Config State
    const pageState = {
        mapName: '',
        startboxConfig: {
            type: '',
            sliderValue: 20,
            jsonIndex: 0
        },
        hillConfig: {
            shape: 'Circle',
            widthProp: 0.2,  // fraction of map width
            heightProp: 0.2, // fraction of map height
            xProp: 0.5,       // normalized center X
            yProp: 0.5        // normalized center Y
        },
        options: {
            startBoxBuildRule: 1,
			hillBuildRule: 2,
			winKingTime: 120,
			captureDelay: 5,
			kingKeepsHill: false,
			noDamageInBoxes: true,
			explodeHillUnits: true,
            allUnitsCaptureQualified: true,
			outputType: "lua",
        }
    };

    // DOM Elements
    const elements = {
        mapSearch: document.getElementById('mapSearch'),
        mapThumb: document.getElementById('mapThumb'),
        mapMenu: document.getElementById('mapMenu'),
        mapTrigger: document.getElementById('mapTrigger'),
        mapDropdown: document.getElementById('mapDropdown'),
        mapImage: document.getElementById('mapImage'),
        mapDisplaySection: document.getElementById('mapDisplaySection'),
        startboxesContainer: document.getElementById('startboxesContainer'),
        hillContainer: document.getElementById('hillContainer'),
        startboxType: document.getElementById('startboxType'),
        startboxSliderContainer: document.getElementById('startboxSliderContainer'),
        startboxSlider: document.getElementById('startboxSlider'),
        startboxSliderValue: document.getElementById('startboxSliderValue'),
        startboxSliderLabel: document.getElementById('startboxSliderLabel'),
        hillType: document.getElementById('hillType'),
        startBoxBuildRule: document.getElementById('startBoxBuildRule'),
		hillBuildRule: document.getElementById('hillBuildRule'),
		winKingTime: document.getElementById('winKingTime'),
		captureDelay: document.getElementById('captureDelay'),
		kingKeepsHill: document.getElementById('kingKeepsHill'),
		noDamageInBoxes: document.getElementById('noDamageInBoxes'),
		explodeHillUnits: document.getElementById('explodeHillUnits'),
        allUnitsCaptureQualified: document.getElementById('allUnitsCaptureQualified'),
		outputTextarea: document.getElementById('output-textarea'),
		outputType: document.getElementById('outputType'),
    };

    // --- MAIN FUNCTION TO BE CALLED ON ANY CHANGE ---
    function onInputChange() {
        pageState.options.startBoxBuildRule = parseInt(elements.startBoxBuildRule.value) || 1;
        pageState.options.hillBuildRule = parseInt(elements.hillBuildRule.value) || 2;
		pageState.options.winKingTime = parseInt(elements.winKingTime.value) || 360;
		pageState.options.captureDelay = parseInt(elements.captureDelay.value) || 15;
		pageState.options.kingKeepsHill = elements.kingKeepsHill.checked;
        pageState.options.noDamageInBoxes = elements.noDamageInBoxes.checked;
		pageState.options.explodeHillUnits = elements.explodeHillUnits.checked;
        pageState.options.allUnitsCaptureQualified = elements.allUnitsCaptureQualified.checked;
		pageState.options.outputType = elements.outputType.value;
		
		let hillAreaArgsLuaTableString
		if(pageState.hillConfig.shape == "Circle") {
			let xProp = pageState.hillConfig.xProp;
			let yProp = pageState.hillConfig.yProp;
			let radius = Math.max(pageState.hillConfig.widthProp, pageState.hillConfig.heightProp)/2.0;
			hillAreaArgsLuaTableString = `{type = "circle", x = ${xProp}, z = ${yProp}, radius = ${radius}}`;
		} else {
			let xProp = pageState.hillConfig.xProp;
			let yProp = pageState.hillConfig.yProp;
			let halfWidthProp = pageState.hillConfig.widthProp/2;
			let halfHeightProp = pageState.hillConfig.heightProp/2;
			let leftProp = xProp - halfWidthProp;
			let rightProp = xProp + halfWidthProp;
			let topProp = yProp - halfHeightProp;
			let bottomProp = yProp + halfHeightProp;
			hillAreaArgsLuaTableString = `{type = "rect", left = ${leftProp}, right = ${rightProp}, top = ${topProp}, bottom = ${bottomProp}}`;
		}
		
        let output = 
`--###KOTH_MODOPTIONS###
KOTHModoptions = {
	hillAreaArgs = ${hillAreaArgsLuaTableString},
	startBoxBuildRule = ${pageState.options.startBoxBuildRule},
	hillBuildRule = ${pageState.options.hillBuildRule},
	winKingTime = ${pageState.options.winKingTime * 1000},
	captureDelay = ${pageState.options.captureDelay * 1000},
	kingKeepsHill = ${pageState.options.kingKeepsHill},
	noDamageInBoxes = ${pageState.options.noDamageInBoxes},
	explodeHillUnits = ${pageState.options.explodeHillUnits},
    allUnitsCaptureQualified = ${pageState.options.allUnitsCaptureQualified},
}
--###KOTH_MODOPTIONS###`;
		
		if(pageState.options.outputType == "base64") {
			let encoder = new TextEncoder();
			let uint8Array = encoder.encode(output);
			output = uint8Array.toBase64({alphabet: "base64url", omitPadding: true});
		}
		
		elements.outputTextarea.innerHTML = output;
		
    }

    // --- INIT ---
    async function init() {
        attachGenericListeners();
        await fetchMaps();
        setupDragAndResize();
        
        window.addEventListener('resize', () => {
            if (currentMap) {
                updateOverlayDimensions();
                updateOverlays();
            }
        });
    }

    async function fetchMaps() {
        try {
            const res = await fetch(MAPS_API);
            mapsData = await res.json();
            populateMapDropdown();
        } catch (e) {
            elements.mapMenu.innerHTML = `<li class="dropdown-loading">Failed to load maps</li>`;
        }
    }

    // --- UI/Dropdown Logic ---
    function populateMapDropdown() {
        elements.mapMenu.innerHTML = '';
        mapsData.forEach((map, index) => {
            const li = document.createElement('li');
            li.className = 'dropdown-option';
            li.innerHTML = `
                <img src="${map.images.preview}" class="option-thumb" alt="thumb">
                <span class="option-title">${map.displayName}</span>
            `;
            li.addEventListener('click', (e) => {
                e.stopPropagation();
                selectMap(map);
                elements.mapDropdown.classList.remove('open');
                elements.mapSearch.value = map.displayName;
                elements.mapThumb.src = map.images.preview;
                elements.mapThumb.style.display = 'block';
                Array.from(elements.mapMenu.children).forEach(opt => opt.classList.remove('is-hidden'));
            });
            elements.mapMenu.appendChild(li);
        });
    }

    elements.mapTrigger.addEventListener('click', () => {
        elements.mapDropdown.classList.add('open');
        elements.mapSearch.focus();
    });

    elements.mapSearch.addEventListener('input', (e) => {
        const query = e.target.value.toLowerCase().trim();
        elements.mapDropdown.classList.add('open');
        Array.from(elements.mapMenu.children).forEach((option) => {
            if (!option.classList.contains('dropdown-option')) return;
            const title = option.querySelector('.option-title').textContent.toLowerCase();
            if (title.includes(query)) option.classList.remove('is-hidden');
            else option.classList.add('is-hidden');
        });
    });

    document.addEventListener('click', (e) => {
        if (!elements.mapDropdown.contains(e.target)) {
            elements.mapDropdown.classList.remove('open');
        }
    });

    // --- MAP SELECTION & SETUP ---
    function selectMap(map) {
        currentMap = map;
        pageState.mapName = map.displayName;
        elements.mapDisplaySection.style.display = 'block';
        
        elements.mapImage.onload = () => {
            imageNaturalRatio = elements.mapImage.naturalWidth / elements.mapImage.naturalHeight;
            updateOverlayDimensions(); // calculate physical bounds first
            resetHillPosition();       // build hill geometry off those bounds
            populateStartboxOptions();
            updateOverlays();
            onInputChange();
        };
        elements.mapImage.src = map.images.preview;
    }

    // --- STARTBOX LOGIC ---
    function populateStartboxOptions() {
        elements.startboxType.innerHTML = '';
        
        if (currentMap.startboxesSet) {
            currentMap.startboxesSet.forEach((set, idx) => {
                const opt = document.createElement('option');
                opt.value = `json_${idx}`;
                opt.textContent = `Default: ${set.maxPlayersPerStartbox} players/box`;
                elements.startboxType.appendChild(opt);
            });
        }

        const modes = ['East vs. West', 'North vs. South', 'NW vs. SE', 'NE vs. SW', '4 Corners', '4 Sides'];
        modes.forEach(m => {
            const opt = document.createElement('option');
            opt.value = m;
            opt.textContent = m;
            elements.startboxType.appendChild(opt);
        });

        elements.startboxType.value = elements.startboxType.options[0].value;
        handleStartboxTypeChange();
    }

    function handleStartboxTypeChange() {
        const val = elements.startboxType.value;
        pageState.startboxConfig.type = val;
        
        if (val.startsWith('json_')) {
            elements.startboxSliderContainer.style.display = 'none';
            pageState.startboxConfig.jsonIndex = parseInt(val.split('_')[1]);
        } else {
            elements.startboxSliderContainer.style.display = 'block';
            if (val === '4 Sides') {
                elements.startboxSlider.max = 33;
                elements.startboxSlider.value = Math.min(elements.startboxSlider.value, 33);
            } else {
                elements.startboxSlider.max = 50;
            }
            elements.startboxSliderValue.textContent = elements.startboxSlider.value;
            pageState.startboxConfig.sliderValue = parseInt(elements.startboxSlider.value);
        }
        updateOverlays();
        onInputChange();
    }

    function generateStartboxes() {
        elements.startboxesContainer.innerHTML = '';
        const type = pageState.startboxConfig.type;
        const val = pageState.startboxConfig.sliderValue;
        let boxesData = []; 

        if (type.startsWith('json_')) {
            const set = currentMap.startboxesSet[pageState.startboxConfig.jsonIndex];
            if (set && set.startboxes) {
                set.startboxes.forEach(box => {
                    let minX = 200, maxX = 0, minY = 200, maxY = 0;
                    box.poly.forEach(pt => {
                        if (pt.x < minX) minX = pt.x;
                        if (pt.x > maxX) maxX = pt.x;
                        if (pt.y < minY) minY = pt.y;
                        if (pt.y > maxY) maxY = pt.y;
                    });
                    boxesData.push({
                        left: (minX / 200) * 100,
                        top: (minY / 200) * 100,
                        width: ((maxX - minX) / 200) * 100,
                        height: ((maxY - minY) / 200) * 100
                    });
                });
            }
        } else if (type === 'East vs. West') {
            boxesData.push({ left: 0, top: 0, width: val, height: 100 });
            boxesData.push({ left: 100 - val, top: 0, width: val, height: 100 });
        } else if (type === 'North vs. South') {
            boxesData.push({ left: 0, top: 0, width: 100, height: val });
            boxesData.push({ left: 0, top: 100 - val, width: 100, height: val });
        } else if (type === 'NW vs. SE') {
            boxesData.push({ left: 0, top: 0, width: val, height: val });
            boxesData.push({ left: 100 - val, top: 100 - val, width: val, height: val });
        } else if (type === 'NE vs. SW') {
            boxesData.push({ left: 100 - val, top: 0, width: val, height: val });
            boxesData.push({ left: 0, top: 100 - val, width: val, height: val });
        } else if (type === '4 Corners') {
            boxesData.push({ left: 0, top: 0, width: val, height: val });
            boxesData.push({ left: 100 - val, top: 0, width: val, height: val });
            boxesData.push({ left: 0, top: 100 - val, width: val, height: val });
            boxesData.push({ left: 100 - val, top: 100 - val, width: val, height: val });
        } else if (type === '4 Sides') {
            boxesData.push({ left: val, top: 0, width: 100 - (val * 2), height: val });
            boxesData.push({ left: val, top: 100 - val, width: 100 - (val * 2), height: val });
            boxesData.push({ left: 0, top: val, width: val, height: 100 - (val * 2) });
            boxesData.push({ left: 100 - val, top: val, width: val, height: 100 - (val * 2) });
        }

        boxesData.forEach(box => {
            const div = document.createElement('div');
            div.className = 'startbox';
            div.style.left = `${(box.left / 100) * overlayRect.width}px`;
            div.style.top = `${(box.top / 100) * overlayRect.height}px`;
            div.style.width = `${(box.width / 100) * overlayRect.width}px`;
            div.style.height = `${(box.height / 100) * overlayRect.height}px`;
            elements.startboxesContainer.appendChild(div);
        });
    }

    // --- HILL LOGIC & DRAGGING/RESIZING ---
    function resetHillPosition() {
        pageState.hillConfig.xProp = 0.5;
        pageState.hillConfig.yProp = 0.5;
        
        // Target an initial dimension 25% of the shortest edge
        const minDim = Math.min(overlayRect.width, overlayRect.height);
        const startSize = minDim * 0.2;
        
        pageState.hillConfig.widthProp = startSize / overlayRect.width;
        pageState.hillConfig.heightProp = startSize / overlayRect.height;
    }

    function renderHill() {
        const isCircle = pageState.hillConfig.shape === 'Circle';
        elements.hillContainer.classList.toggle('is-circle', isCircle);

        const w = pageState.hillConfig.widthProp * overlayRect.width;
        const h = pageState.hillConfig.heightProp * overlayRect.height;
        const px = pageState.hillConfig.xProp * overlayRect.width;
        const py = pageState.hillConfig.yProp * overlayRect.height;

        // Align coordinates perfectly on top of dynamically centered map 
        elements.hillContainer.style.width = `${w}px`;
        elements.hillContainer.style.height = `${h}px`;
        elements.hillContainer.style.left = `${overlayRect.left + px - (w / 2)}px`;
        elements.hillContainer.style.top = `${overlayRect.top + py - (h / 2)}px`;
    }

    function setupDragAndResize() {
        let isDragging = false;
        let isResizing = false;
        let startMouseX = 0, startMouseY = 0;
        let startConfigX = 0, startConfigY = 0, startWidthProp = 0, startHeightProp = 0;

        elements.hillContainer.addEventListener('mousedown', (e) => {
            if (e.target.id === 'hillResizeHandle') {
                isResizing = true;
            } else {
                isDragging = true;
            }
            startMouseX = e.clientX;
            startMouseY = e.clientY;
            startConfigX = pageState.hillConfig.xProp;
            startConfigY = pageState.hillConfig.yProp;
            startWidthProp = pageState.hillConfig.widthProp;
            startHeightProp = pageState.hillConfig.heightProp;
            e.preventDefault();
        });

        document.addEventListener('mousemove', (e) => {
            if (!isDragging && !isResizing) return;
            
            const dx = e.clientX - startMouseX;
            const dy = e.clientY - startMouseY;
            
            if (isDragging) {
                const wProp = pageState.hillConfig.widthProp;
                const hProp = pageState.hillConfig.heightProp;
                
                let newX = startConfigX + (dx / overlayRect.width);
                let newY = startConfigY + (dy / overlayRect.height);
                
                // Clamp position tightly against map borders
                pageState.hillConfig.xProp = Math.max(wProp / 2, Math.min(1 - (wProp / 2), newX));
                pageState.hillConfig.yProp = Math.max(hProp / 2, Math.min(1 - (hProp / 2), newY));

            } else if (isResizing) {
                const origW = startWidthProp * overlayRect.width;
                const origH = startHeightProp * overlayRect.height;
                const origLeft = (startConfigX - (startWidthProp / 2)) * overlayRect.width;
                const origTop = (startConfigY - (startHeightProp / 2)) * overlayRect.height;

                let newW = origW + dx;
                let newH = origH + dy;

                // Force uniform limits for circles
                if (pageState.hillConfig.shape === 'Circle') {
                    const size = Math.max(newW, newH);
                    newW = size;
                    newH = size;
                }

                // Hard limits (Min 30px, Max constraints at the bottom/right edges of map)
                newW = Math.max(30, newW);
                newH = Math.max(30, newH);
                newW = Math.min(newW, overlayRect.width - origLeft);
                newH = Math.min(newH, overlayRect.height - origTop);

                // If clamping distorted a circle, correct it down to the smallest clamped axis
                if (pageState.hillConfig.shape === 'Circle') {
                    const clampedSize = Math.min(newW, newH);
                    newW = clampedSize;
                    newH = clampedSize;
                }

                pageState.hillConfig.widthProp = newW / overlayRect.width;
                pageState.hillConfig.heightProp = newH / overlayRect.height;
                
                // Pin the top-left coordinate to scale outward organically
                pageState.hillConfig.xProp = (origLeft + (newW / 2)) / overlayRect.width;
                pageState.hillConfig.yProp = (origTop + (newH / 2)) / overlayRect.height;
            }
            
            renderHill();
        });

        document.addEventListener('mouseup', () => {
            if (isDragging || isResizing) onInputChange();
            isDragging = false;
            isResizing = false;
        });
    }

    // --- OVERLAY CONTAINER UPDATER ---
    function updateOverlayDimensions() {
        if (!currentMap) return;
        const imgRect = elements.mapImage.getBoundingClientRect();
        const containerRect = elements.mapImage.parentElement.getBoundingClientRect();
        
        overlayRect.width = imgRect.width;
        overlayRect.height = imgRect.height;
        overlayRect.left = imgRect.left - containerRect.left;
        overlayRect.top = imgRect.top - containerRect.top;
    }

    function updateOverlays() {
        if (!currentMap) return;
        
        elements.startboxesContainer.style.width = `${overlayRect.width}px`;
        elements.startboxesContainer.style.height = `${overlayRect.height}px`;
        elements.startboxesContainer.style.left = `${overlayRect.left}px`;
        elements.startboxesContainer.style.top = `${overlayRect.top}px`;
        elements.startboxesContainer.style.position = 'absolute';
        
        generateStartboxes();
        renderHill();
    }

    // --- GENERIC EVENT BINDING ---
    function attachGenericListeners() {
        elements.startboxType.addEventListener('change', handleStartboxTypeChange);
        
        elements.startboxSlider.addEventListener('input', (e) => {
            elements.startboxSliderValue.textContent = e.target.value;
            pageState.startboxConfig.sliderValue = parseInt(e.target.value);
            updateOverlays();
            onInputChange();
        });

        elements.hillType.addEventListener('change', () => {
            pageState.hillConfig.shape = elements.hillType.value;
            // Snap a rectangle back into a proportional circle automatically if needed
            if (pageState.hillConfig.shape === 'Circle') {
                const w = pageState.hillConfig.widthProp * overlayRect.width;
                const h = pageState.hillConfig.heightProp * overlayRect.height;
                const size = Math.min(w, h);
                pageState.hillConfig.widthProp = size / overlayRect.width;
                pageState.hillConfig.heightProp = size / overlayRect.height;
            }
            renderHill();
            onInputChange();
        });

        elements.startBoxBuildRule.addEventListener('change', onInputChange);
		elements.hillBuildRule.addEventListener('change', onInputChange);
		elements.winKingTime.addEventListener('input', onInputChange);
		elements.captureDelay.addEventListener('input', onInputChange);
		elements.kingKeepsHill.addEventListener('change', onInputChange);
		elements.noDamageInBoxes.addEventListener('change', onInputChange);
		elements.explodeHillUnits.addEventListener('change', onInputChange);
        elements.allUnitsCaptureQualified.addEventListener('change', onInputChange);
		elements.outputType.addEventListener('change', onInputChange);
    }

    // Boot
    init();
});