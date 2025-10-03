let currentDevices = [];
let barChart, pieChart, topAppsChart;
let currentSort = { column: 4, ascending: false }; // Default sort is now Total (new index)
let availableMonths = [];
let currentMonthIndex = -1;
let sevenDayDataGlobal = null; // New global variable for sevenDayData
let currentDisplayStartDate = ''; // New global variable
let currentDisplayEndDate = '';   // New global variable
let currentImageLanguage = 'en'; // Default language for saved image
let routerTodayFormatted = ''; // Global variable to store router's current date
let currentDaysInPeriod = 0;
let currentFilterType = 'all_time';

const originalModalState = new Map();

const translations = {
    'Personalized Usage Summary': 'ملخص الاستخدام الشخصي',
    'Device vs. Others': 'رسم بياني للمقارنة',
    'Since Month Began:': 'إستخدامك منذ بداية الشهر:',
    'Top 3 Apps (Today)': 'أكثر 3 تطبيقات (اليوم)',
    'Top 3 Apps (Yesterday)': 'أكثر 3 تطبيقات (الأمس)',
    'Top 3 Apps (Last 7 Days)': 'أكثر 3 تطبيقات (آخر 7 أيام)',
    'Top 3 Apps (This Month)': 'أكثر 3 تطبيقات (هذا الشهر)',
    'Top 3 Apps (All Time)': 'أكثر 3 تطبيقات (منذ حفظ الأرشيف)',
    'Top 3 Apps (Current Period)': 'أكثر 3 تطبيقات (للفترة الحالية)',
    'No app data available': 'لا توجد بيانات للتطبيق',
    'Save as Image': 'حفظ الصورة',
    'Netflix': 'نتفليكس',
    'Google': 'جوجل',
    'Youtube': 'يوتيوب',
    'Google Play': 'متجر جوجل بلاي',
    'Facebook': 'فيسبوك',
    'Instagram': 'انستغرام',
    'WhatsApp': 'واتساب',
    'Zoom': 'زووم',
    'Google Drive': 'جوجل درايف',
    'Google APIs(SSL)': 'بروتوكولات جوجل الآمنة',
    'Google Static Content(SSL)': 'خدمات جوجل آخري',
    'DNS': 'دى إن إس',
    'X': 'إكس',
    'Safari': 'سفاري',
    'Apple.com': 'آبل دوت كوم',
    'Apple App Store': 'متجر تطبيقات آبل',
    'iTunes/App Store': 'متجر آبل',
    'Microsoft.com': 'ميكروسوفت دوت كوم',
    'Windows Update': 'تحديثات ويندوز',
    'Vimeo': 'منصة فيديو Vimeo',
    'Steam': 'ستيم',
    'Xbox Live': 'إكس بوكس لايف',
    'Chrome': 'كروم',
    'Spotify': 'سبوتيفاي',
    'Snapchat': 'سناب شات',
    'TikTok': 'تيك توك',
    'Other Sources': 'مصادر أخرى'
};

function applyArabicTranslation() {
    const summaryContainer = document.querySelector('#deviceCardModalContent .summary-section');
    if (!summaryContainer) return;

    revertToEnglish(); // Ensure a clean state before applying

    const elementsToTranslate = summaryContainer.querySelectorAll('h3, h4, .js-localize-monthly-usage-label, .app-name, #saveSummaryImageBtn');

    elementsToTranslate.forEach(el => {
        const originalText = el.textContent.trim();
        const translatedText = translations[originalText];
        if (translatedText) {
            originalModalState.set(el, { text: originalText, style: { direction: el.style.direction, textAlign: el.style.textAlign } });
            el.textContent = translatedText;
        }
    });

    const rtlContainers = summaryContainer.querySelectorAll('.summary-section, .monthly-usage, .top-apps, .app-list, h3, h4, .app-list li');
    rtlContainers.forEach(el => {
        if (!originalModalState.has(el)) {
            originalModalState.set(el, { style: { direction: el.style.direction, textAlign: el.style.textAlign } });
        }
        el.style.direction = 'rtl';
        el.style.textAlign = 'right';
    });

    // Translate GB/MB units in text nodes
    const walker = document.createTreeWalker(summaryContainer, NodeFilter.SHOW_TEXT, null, false);
    let node;
    while (node = walker.nextNode()) {
        const originalText = node.nodeValue;
        let newText = originalText;
        let changed = false;

        if (newText.includes(' GB')) {
            newText = newText.replace(/ GB/g, ' جيجا');
            changed = true;
        }
        if (newText.includes(' MB')) {
            newText = newText.replace(/ MB/g, ' ميجا');
            changed = true;
        }

        if (changed) {
            if (!originalModalState.has(node)) {
                originalModalState.set(node, { text: originalText });
            }
            node.nodeValue = newText;
        }
    }
}

function revertToEnglish() {
    if (originalModalState.size === 0) return;

    originalModalState.forEach((state, el) => {
        if (state.text) {
            if (el.nodeType === Node.TEXT_NODE) {
                el.nodeValue = state.text;
            } else {
                el.textContent = state.text;
            }
        }
        if (state.style) {
            el.style.direction = state.style.direction || '';
            el.style.textAlign = state.style.textAlign || '';
        }
    });

    originalModalState.clear();
}

function dismissRestoreWarning() {
    const warningBanner = document.getElementById('restore-warning');
    if (currentRestoreEventMessage) {
        localStorage.setItem('dismissedRestoreEvent', currentRestoreEventMessage);
    }
    warningBanner.style.display = 'none';
}

function checkRestoreStatus() {
    fetch('data/last_restore.txt')
        .then(response => {
            if (!response.ok) { throw new Error('No restore file'); }
            return response.text();
        })
        .then(text => {
            if (text.trim()) {
                const [detected, restored, backup] = text.trim().split('|');
                const message = `⚠️ Database corruption detected at ${detected}, restored at ${restored} from ${backup}`;
                
                const dismissedEvent = localStorage.getItem('dismissedRestoreEvent');

                if (message !== dismissedEvent) {
                    currentRestoreEventMessage = message; // Set the global variable
                    document.getElementById('restore-message').textContent = message;
                    document.getElementById('restore-warning').style.display = 'flex';
                }
            }
        })
        .catch(() => {
            // This is normal operation, do nothing if the file doesn't exist
        });
}

function viewRestoreHistory() {
    fetch('logs/db_restore_history.log')
        .then(response => {
            if (!response.ok) { throw new Error('No history log'); }
            return response.text();
        })
        .then(log => {
            // Colorize the log content for better readability
            const colorizedLog = log.split('\n').map(line => {
                // Escape HTML entities for security
                const escapedLine = line
                    .replace(/&/g, '&amp;')
                    .replace(/</g, '&lt;')
                    .replace(/>/g, '&gt;')
                    .replace(/"/g, '&quot;')
                    .replace(/'/g, '&#039;');
                    
                if (line.includes('RESTORED')) {
                    return `<span style="color: #4CAF50; font-weight: bold;">${escapedLine}</span>`; // Green for successful restores
                } else if (line.includes('FAILED') || line.includes('CRITICAL')) {
                    return `<span style="color: #F44336; font-weight: bold;">X ${escapedLine}</span>`; // Red with X for critical failures
                } else if (line.includes('missing') || line.includes('corrupt')) {
                    return `<span style="color: #F44336; font-weight: bold;">${escapedLine}</span>`; // Red for database issues
                } else if (line.includes('DETECTED') || line.includes('TIME GAP')) {
                    return `<span style="color: #FF9800; font-weight: bold;">${escapedLine}</span>`; // Yellow for informational messages
                } else {
                    return escapedLine; // Default styling for other lines
                }
            }).join('\n');
            
            document.getElementById('history-log-content').innerHTML = colorizedLog || 'No restore events recorded.';
            document.getElementById('history-modal').style.display = 'block';
        })
        .catch(() => {
            document.getElementById('history-log-content').textContent = 'Could not load restore history log.';
            document.getElementById('history-modal').style.display = 'block';
        });
}

let selectedDailyDate = '';

function closeHistoryModal() {
    document.getElementById('history-modal').style.display = 'none';
}

function generatePersonalizedSummary(device, allDevices) {
    // Calculate device vs others data
    const deviceUsage = device.total || 0;
    const totalUsage = allDevices.reduce((sum, d) => sum + (d.total || 0), 0);
    const othersUsage = totalUsage - deviceUsage;

    // Fetch and display monthly usage
    const firstDayOfMonth = `${routerTodayFormatted.substring(0, 7)}-01`;
    const todayFormatted = routerTodayFormatted;
    const monthlyDataFilename = `traffic_period_${firstDayOfMonth}_${todayFormatted}.json`;

    fetchData(monthlyDataFilename).then(monthlyData => {
        let deviceMonthlyUsage = 0;
        if (monthlyData && monthlyData.devices) {
            const monthlyDevice = monthlyData.devices.find(d => d.mac === device.mac);
            if (monthlyDevice) {
                deviceMonthlyUsage = monthlyDevice.total;
            }
        }
        const monthlyUsageElement = document.getElementById('monthlyUsageValue');
        if(monthlyUsageElement) monthlyUsageElement.textContent = formatBytes(deviceMonthlyUsage);
    });
    
    // Determine period label based on filter type
    let periodLabel = 'Current Period';
    switch (currentFilterType) {
        case 'today':
            periodLabel = 'Today';
            break;
        case 'yesterday':
            periodLabel = 'Yesterday';
            break;
        case 'last_7_days':
            periodLabel = 'Last 7 Days';
            break;
        case 'this_month':
            periodLabel = 'This Month';
            break;
        default:
            if (currentFilterType.startsWith('month_')) {
                periodLabel = 'This Month';
            } else if (currentFilterType === 'all_time') {
                periodLabel = 'All Time';
            } else if (/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(currentFilterType)) {
                periodLabel = currentFilterType;
            }
            break;
    }

    return `
        <div class="summary-section">
            <h3>Personalized Usage Summary</h3>
            <div class="summary-controls-row">
                <div id="summaryTitleInput" contenteditable="true" placeholder="Enter title for screenshot..." class="editable-title"></div>
                <button id="saveSummaryImageBtn" onclick="saveSummaryImage()">Save as Image</button>
            </div>
            <div class="summary-controls-row" id="emoji-controls-row">
                <div class="language-toggle">
                    <button id="lang-en-btn" class="active">EN</button>
                    <button id="lang-ar-btn">AR</button>
                </div>
                <div style="position: relative;">
                    <button id="emoji-btn">😊</button>
                </div>
                <div id="selected-emojis"></div>
                <button id="remove-emoji-feature-btn">&times;</button>
            </div>
            
            <h4>Device vs. Others</h4>
            <div class="chart-container-modal">
                <canvas id="deviceVsOthersChart"></canvas>
            </div>
            
            <div class="monthly-usage">
                <span class="js-localize-monthly-usage-label">Since Month Began:</span> <span id="monthlyUsageValue" class="monthly-usage-value">Loading...</span>
            </div>
            
            <div class="top-apps">
                <h4>Top 3 Apps (${periodLabel})</h4>
                <ul class="app-list" id="topAppsList">
                    <li>Loading apps data...</li>
                </ul>
            </div>
        </div>
    `;
}

function showDeviceCardModal(macAddress, isMobileView = false) {
    const device = currentDevices.find(d => d.mac === macAddress);
    if (device) {
        const modal = document.getElementById('deviceCardModal');
        const modalContent = document.getElementById('deviceCardModalContent');
        const deviceCardHtml = renderDeviceCards([device], currentDaysInPeriod);
        const personalizedSummaryHtml = generatePersonalizedSummary(device, currentDevices);

        // For mobile view, show only the personalized summary
        const modalHtml = isMobileView ? `
            <div class="modal-header">
                <!-- Title removed as per user request - Last used: Device Split View -->
            </div>
            <div class="modal-body">
                <div class="mobile-summary-view">
                    ${personalizedSummaryHtml}
                    <div class="mobile-warning-message">
                        <p>⚠️ Mobile view has limited quality. Switch to desktop mode for crisp images.</p>
                    </div>
                </div>
            </div>
        ` : `
            <div class="modal-header">
                <!-- Title removed as per user request - Last used: Device Split View -->
            </div>
            <div class="modal-body">
                <div class="split-view">
                    <div class="device-overview-panel">
                        <h3>Device Overview</h3>
                        <div class="device-card-wrapper">${deviceCardHtml}</div>
                    </div>
                    <div>${personalizedSummaryHtml}</div>
                </div>
            </div>
        `;

        modalContent.innerHTML = modalHtml;
        
        // Add or remove mobile view class
        if (isMobileView) {
            modal.classList.add('mobile-view');
        } else {
            modal.classList.remove('mobile-view');
        }

        modal.style.display = 'flex';

        // Initialize the chart after modal is displayed
        setTimeout(() => {
            console.log('Attempting to initialize chart...');
            const canvasInHTML = modalContent.innerHTML.includes('deviceVsOthersChart');
            console.log('Canvas element exists in HTML:', canvasInHTML);

            if (canvasInHTML) {
                const canvasElement = document.getElementById('deviceVsOthersChart');
                console.log('Canvas element found in DOM:', !!canvasElement);
                if (canvasElement) {
                    console.log('Canvas dimensions:', canvasElement.width, 'x', canvasElement.height);
                }
            }

            initDeviceVsOthersChart(device, currentDevices);
        }, 200);

        // Fetch and render device apps
        fetchAndRenderDeviceApps(macAddress);
        initEmojiPicker();

        // Language Toggle Event Listeners (moved here to ensure elements exist)
        const langEnBtn = document.getElementById('lang-en-btn');
        const langArBtn = document.getElementById('lang-ar-btn');

        if (langEnBtn && langArBtn) {
            langEnBtn.addEventListener('click', () => {
                revertToEnglish();
                langEnBtn.classList.add('active');
                langArBtn.classList.remove('active');
            });

            langArBtn.addEventListener('click', () => {
                applyArabicTranslation();
                langArBtn.classList.add('active');
                langEnBtn.classList.remove('active');
            });
        }

        // Ensure the modal starts in English view
        revertToEnglish();
    }
}

function initDeviceVsOthersChart(device, allDevices) {
    console.log('initDeviceVsOthersChart called for device:', device.name);

    // Check if Chart.js is loaded
    if (typeof Chart === 'undefined') {
        console.error('Chart.js is not loaded!');
        return;
    }

    const deviceUsage = device.total || 0;
    const totalUsage = allDevices.reduce((sum, d) => sum + (d.total || 0), 0);
    const othersUsage = totalUsage - deviceUsage;

    console.log('Chart data:', { deviceUsage, othersUsage, totalUsage });

    const ctx = document.getElementById('deviceVsOthersChart');
    console.log('Canvas element found:', !!ctx);
    if (!ctx) {
        console.error('Chart canvas not found!');
        return;
    }

    // Destroy existing chart if it exists
    if (window.deviceVsOthersChart && typeof window.deviceVsOthersChart.destroy === 'function') {
        window.deviceVsOthersChart.destroy();
    }

    window.deviceVsOthersChart = new Chart(ctx.getContext('2d'), {
        type: 'doughnut',
        data: {
            labels: [device.name || 'This Device', 'Other Devices'],
            datasets: [{
                data: [deviceUsage, othersUsage],
                backgroundColor: ['#0d6efd', '#6c757d'],
                hoverOffset: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        boxWidth: 12,
                        padding: 10,
                        font: {
                            size: 12
                        },
                        usePointStyle: true,
                        textAlign: 'left'
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const value = context.raw || 0;
                            const total = context.dataset.data.reduce((sum, val) => sum + val, 0);
                            const percentage = total > 0 ? (value / total * 100).toFixed(1) : 0;
                            return `${formatBytes(value)} (${percentage}%)`;
                        }
                    }
                }
            }
        },
        plugins: [{
            id: 'centerText',
            afterDraw: function (chart) {
                const ctx = chart.ctx;
                const meta = chart.getDatasetMeta(0);
                if (meta && meta.data && meta.data[0]) {
                    const element = meta.data[0];
                    const data = chart.data.datasets[0].data[0];
                    const total = chart.data.datasets[0].data.reduce((sum, val) => sum + val, 0);
                    const percentage = total > 0 ? (data / total * 100).toFixed(1) : 0;

                    // Get the tooltip position which is in the center of the slice
                    const position = element.tooltipPosition();

                    ctx.save();
                    ctx.fillStyle = '#fff';
                    ctx.font = 'bold 14px Arial';
                    ctx.textAlign = 'center';
                    ctx.textBaseline = 'middle';
                    ctx.strokeStyle = 'rgba(0, 0, 0, 0.8)';
                    ctx.lineWidth = 3;
                    ctx.strokeText(percentage + '%', position.x, position.y);
                    ctx.fillText(percentage + '%', position.x, position.y);
                    ctx.restore();
                }
            }
        }]
    });
}

function saveSummaryImage() {
    const summaryContainer = document.querySelector('#deviceCardModalContent .summary-section');
    const modal = document.getElementById('deviceCardModal');
    const modalContent = document.querySelector('#deviceCardModal .modal-content');
    const titleInput = document.getElementById('summaryTitleInput');
    const saveButton = document.getElementById('saveSummaryImageBtn');
    const originalTitle = titleInput.textContent.trim();
    const titleForImage = originalTitle || 'Device Usage Summary';

    // Temporarily hide the input and button
    titleInput.style.display = 'none';
    saveButton.style.display = 'none';

    // Hide emoji controls and picker
    const emojiControlsRow = document.getElementById('emoji-controls-row');
    const emojiPicker = document.getElementById('emoji-picker');
    if (emojiControlsRow) emojiControlsRow.style.display = 'none';
    if (emojiPicker) emojiPicker.style.display = 'none';

    // Temporarily create a div for the title to be included in the screenshot
    const titleElement = document.createElement('h2');
    titleElement.style.display = 'block';
    titleElement.style.margin = '15px auto 25px auto';
    titleElement.style.color = '#2c3e50';
    titleElement.style.fontSize = '24px';
    titleElement.style.fontFamily = '"Segoe UI", Arial, sans-serif';
    titleElement.style.fontWeight = '400';
    titleElement.style.textShadow = '1px 1px 2px rgba(0,0,0,0.1)';
    titleElement.style.padding = '10px 15px';
    titleElement.style.backgroundColor = 'rgba(240, 240, 240, 0.8)';
    titleElement.style.borderRadius = '5px';
    titleElement.style.width = '100%';
    titleElement.style.textAlign = 'center';
    titleElement.style.boxSizing = 'border-box';
    titleElement.style.marginLeft = '0';
    titleElement.style.marginRight = '0';

    // Add selected emojis to the title element on a new line
    const selectedEmojisContainer = document.getElementById('selected-emojis');
    const selectedEmojis = selectedEmojisContainer.textContent.trim();
    if (selectedEmojis) {
        titleElement.innerHTML = `📄 ${titleForImage}<br><span style="font-size: 20px;">${selectedEmojis}</span>`;
    } else {
        titleElement.textContent = `📄 ${titleForImage}`;
    }

    // Insert the title element at the beginning of the summary container for screenshot
    summaryContainer.prepend(titleElement);

    // Sanitize filename
    let sanitizedFilename = titleForImage
        .replace(/[^a-zA-Z0-9\s-_]/g, '')
        .replace(/\s+/g, '_')
        .replace(/__+/g, '_')
        .replace(/^-+|-+$/g, '')
        .replace(/^_|_$/g, '');

    if (sanitizedFilename === '') {
        sanitizedFilename = 'Device_Summary_Report';
    }

    // Check if this is mobile view
    const isMobileView = modal && modal.classList.contains('mobile-view');
    
    // Store original transform and remove it for screenshot
    let originalTransform = '';
    if (modalContent) {
        const computedTransform = window.getComputedStyle(modalContent).transform;
        if (computedTransform && computedTransform !== 'none') {
            originalTransform = computedTransform;
        }
        // Always explicitly set transform to none during capture
        modalContent.style.transform = 'none';
    }

    if (isMobileView) {
        // Enhanced quality for mobile devices only
        domtoimage.toJpeg(summaryContainer, {
            quality: 1.0,
            bgcolor: '#ffffff',
            width: summaryContainer.scrollWidth * 1.5, // 1.5x scaling for better balance
            height: summaryContainer.scrollHeight * 1.5, // 1.5x scaling for better balance
            style: {
                transform: 'scale(1.5)', // Scale up content to match the higher resolution
                transformOrigin: 'top left',
                background: '#ffffff',
                zoom: 1 // No zoom effect
            }
        }).then(function (dataUrl) {
            // Remove the temporary title element after image is generated
            titleElement.remove();

            // Restore visibility of emoji controls and picker
            if (emojiControlsRow) emojiControlsRow.style.display = '';
            if (emojiPicker) emojiPicker.style.display = '';

            const link = document.createElement('a');
            link.download = `${sanitizedFilename}.jpg`;
            link.href = dataUrl;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }).catch(function (error) {
            console.error('Error generating image:', error);
            alert('Failed to save image. Please try again.');
            titleElement.remove();
            if (selectedEmojis) {
                const emojiElement = summaryContainer.querySelector('div[style*="font-size: 24px"]');
                if (emojiElement) {
                    emojiElement.remove();
                }
            }
        }).finally(() => {
            // Always restore visibility of input and button
            titleInput.style.display = '';
            saveButton.style.display = '';

            // Restore visibility of emoji controls and picker
            if (emojiControlsRow) emojiControlsRow.style.display = '';
            if (emojiPicker) emojiPicker.style.display = '';

            // Restore original transform
            if (originalTransform !== undefined) {
                modalContent.style.transform = originalTransform;
            } else {
                modalContent.style.transform = ''; // Reset to default if no original transform
            }
        });
    } else {
        // Original quality for desktop devices
        domtoimage.toJpeg(summaryContainer, {
            quality: 0.9,
            bgcolor: '#ffffff',
            style: {
                transform: 'scale(1)',
                transformOrigin: 'center',
                background: '#ffffff'
            }
        }).then(function (dataUrl) {
            // Remove the temporary title element after image is generated
            titleElement.remove();

            // Restore visibility of emoji controls and picker
            if (emojiControlsRow) emojiControlsRow.style.display = '';
            if (emojiPicker) emojiPicker.style.display = '';

            const link = document.createElement('a');
            link.download = `${sanitizedFilename}.jpg`;
            link.href = dataUrl;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }).catch(function (error) {
            console.error('Error generating image:', error);
            alert('Failed to save image. Please try again.');
            titleElement.remove();
            if (selectedEmojis) {
                const emojiElement = summaryContainer.querySelector('div[style*="font-size: 24px"]');
                if (emojiElement) {
                    emojiElement.remove();
                }
            }
        }).finally(() => {
            // Always restore visibility of input and button
            titleInput.style.display = '';
            saveButton.style.display = '';

            // Restore visibility of emoji controls and picker
            if (emojiControlsRow) emojiControlsRow.style.display = '';
            if (emojiPicker) emojiPicker.style.display = '';

            // Restore original transform if it was changed
            if (originalTransform) {
                modalContent.style.transform = originalTransform;
            }
        });
    }
}

function initEmojiPicker() {
    const emojiBtn = document.getElementById('emoji-btn');
    const selectedEmojisContainer = document.getElementById('selected-emojis');
    const removeEmojiFeatureBtn = document.getElementById('remove-emoji-feature-btn');
    let emojiPicker = document.getElementById('emoji-picker');

    const emojis = ['😊', '😂', '😍', '🤔', '😢', '😠', '👍', '👎', '❤️', '💔', '🔥', '💯'];

    emojiBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        if (!emojiPicker) {
            emojiPicker = document.createElement('div');
            emojiPicker.id = 'emoji-picker';
            emojis.forEach(emoji => {
                const emojiSpan = document.createElement('span');
                emojiSpan.className = 'emoji';
                emojiSpan.textContent = emoji;
                emojiSpan.addEventListener('click', () => {
                    const selectedEmojiSpan = document.createElement('span');
                    selectedEmojiSpan.className = 'selected-emoji';
                    selectedEmojiSpan.textContent = emoji;
                    selectedEmojiSpan.addEventListener('click', () => {
                        selectedEmojisContainer.removeChild(selectedEmojiSpan);
                    });
                    selectedEmojisContainer.appendChild(selectedEmojiSpan);
                });
                emojiPicker.appendChild(emojiSpan);
            });
            emojiBtn.parentElement.appendChild(emojiPicker);
        }
        emojiPicker.style.display = emojiPicker.style.display === 'block' ? 'none' : 'block';
    });

    removeEmojiFeatureBtn.addEventListener('click', () => {
        const emojiControlsRow = document.getElementById('emoji-controls-row');
        if (emojiControlsRow) {
            emojiControlsRow.remove();
        }
        if (emojiPicker) {
            emojiPicker.remove();
        }
    });

    document.addEventListener('click', (event) => {
        if (emojiPicker && !emojiPicker.contains(event.target) && event.target !== emojiBtn) {
            emojiPicker.style.display = 'none';
        }
    });
}

async function fetchAndRenderDeviceApps(macAddress) {
    try {
        // Use the same date range logic as the old implementation
        const currentPeriodStart = currentDisplayStartDate;
        const currentPeriodEnd = currentDisplayEndDate;

        if (!currentPeriodStart || !currentPeriodEnd) {
            renderTopAppsList([]);
            return;
        }

        const response = await fetch(`/skyhero-v2/get_device_apps.sh?mac=${macAddress}&start=${currentPeriodStart}&end=${currentPeriodEnd}`);
        if (response.ok) {
            const appData = await response.json();
            renderTopAppsList(appData.apps || []);
        } else {
            console.error(`Failed to fetch device apps: ${response.status} ${response.statusText}`);
            renderTopAppsList([]);
        }
    } catch (error) {
        console.error('Error fetching device apps:', error);
        renderTopAppsList([]);
    }
}

function renderTopAppsList(apps) {
    const topAppsListElement = document.getElementById('topAppsList');
    if (!topAppsListElement) return;

    topAppsListElement.innerHTML = ''; // Clear previous list

    if (apps && apps.length > 0) {
        apps.slice(0, 3).forEach(app => { // Display top 3 apps
            const listItem = document.createElement('li');
            listItem.innerHTML = `
                <span class="app-name">${app.name}</span>
                <span class="app-usage">${formatBytes(app.total)}</span>
            `;
            topAppsListElement.appendChild(listItem);
        });
    } else {
        const listItem = document.createElement('li');
        listItem.innerHTML = '<span class="app-name">No app data available</span><span class="app-usage">-</span>';
        topAppsListElement.appendChild(listItem);
    }
}

function closeDeviceCardModal() {
    console.log('Closing device card modal');
    // Destroy the chart before closing modal
    if (window.deviceVsOthersChart && typeof window.deviceVsOthersChart.destroy === 'function') {
        window.deviceVsOthersChart.destroy();
        window.deviceVsOthersChart = null;
    }

    document.getElementById('deviceCardModal').style.display = 'none';
    document.getElementById('deviceCardModalContent').innerHTML = ''; // Clear content
}

// Close modal when clicking outside
document.getElementById('deviceCardModal').addEventListener('click', function (event) {
    if (event.target === this) {
        closeDeviceCardModal();
    }
});

function showDailyBreakdownModal(date) {
    selectedDailyDate = date;
    document.getElementById('dailyBreakdownMessage').textContent = `Do you want to view data for ${date}?`;
    document.getElementById('dailyBreakdownModal').style.display = 'flex';
}

function closeDailyBreakdownModal() {
    document.getElementById('dailyBreakdownModal').style.display = 'none';
    selectedDailyDate = '';
}

async function confirmDailyBreakdown() {
    const dateToFilter = selectedDailyDate; // Store the date before clearing
    closeDailyBreakdownModal(); // This will clear selectedDailyDate
    console.log("Confirming daily breakdown for date: ", dateToFilter);
    if (dateToFilter) {
        await applyFilter(dateToFilter); // Apply filter for the stored date
    }
}

async function initMonthNavigator() {
    console.log("initMonthNavigator called.");
    try {
        const response = await fetch('get_available_months.sh');
        availableMonths = await response.json();
        console.log("Available months fetched:", availableMonths);

        if (availableMonths.length > 0) {
            // Sort months in descending order (most recent first)
            availableMonths.sort((a, b) => b.localeCompare(a));
            currentMonthIndex = 0; // Start with the most recent month
            const monthNavigator = document.getElementById('month-navigator');
            if (monthNavigator) {
                monthNavigator.style.display = 'flex';
                console.log("Month navigator display set to flex.");
            } else {
                console.error("Month navigator element not found!");
            }
            updateMonthNavigator();
            loadMonthData(); // Load data for the initial month
        } else {
            const monthNavigator = document.getElementById('month-navigator');
            if (monthNavigator) {
                monthNavigator.style.display = 'none';
                console.log("No available months, month navigator hidden.");
            }
            // If no monthly data, default to 'this_month' quick filter
            applyFilter('this_month');
        }
    } catch (error) {
        console.error('Error fetching available months:', error);
        const monthNavigator = document.getElementById('month-navigator');
        if (monthNavigator) {
            monthNavigator.style.display = 'none';
        }
        // Fallback to 'this_month' quick filter if fetching fails
        applyFilter('this_month');
    }
}

const monthNames = ["January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
];

function updateMonthNavigator() {
    if (currentMonthIndex === -1) return;

    const [year, month] = availableMonths[currentMonthIndex].split('-');
    const monthName = monthNames[parseInt(month) - 1]; // Get month name from array

    document.getElementById('current-month-display').textContent = `${monthName} ${year}`;
    document.getElementById('prev-month').disabled = (currentMonthIndex === availableMonths.length - 1);
    document.getElementById('next-month').disabled = (currentMonthIndex === 0);
}

function loadMonthData() {
    if (currentMonthIndex === -1) return;
    const monthId = availableMonths[currentMonthIndex]; // e.g., "2025-08"
    const currentYearMonth = new Date().toISOString().slice(0, 7); // e.g., "2025-08"

    if (monthId === currentYearMonth) {
        // If the selected month is the current month, use the 'this_month' quick filter
        // which is updated more frequently by traffic_monitor.sh
        applyFilter('this_month');
    } else {
        // For past months, use the pre-aggregated monthly file
        applyFilter(`month_${monthId}`);
    }
}

function updateQuotaDisplay(stats, filterType) {
    const quotaCard = document.querySelector('.quota-card');

    if (!quotaCard) {
        return; // Exit if the card element doesn't exist
    }

    // If filter is 'all_time', hide the entire card.
    if (filterType === 'all_time') {
        quotaCard.style.display = 'none';
        return;
    }

    // Otherwise, ensure the card is visible and proceed with the normal logic.
    quotaCard.style.display = 'block';

    const quotaUsedElement = document.getElementById('quotaUsed');
    const quotaTotalElement = document.getElementById('quotaTotal');
    const quotaProgressBar = document.getElementById('quotaProgressBar');
    const quotaMessageElement = document.getElementById('quotaMessage');

    if (!stats || !stats.monthlyQuotaGB) {
        // Hide quota card if no quota data is available for other views
        quotaCard.style.display = 'none';
        return;
    }

    const totalTrafficGB = stats.traffic;
    const monthlyQuotaGB = stats.monthlyQuotaGB;
    const percentageUsed = (totalTrafficGB / monthlyQuotaGB) * 100;

    quotaUsedElement.textContent = `${totalTrafficGB.toFixed(1)} GB`;
    quotaTotalElement.textContent = `${monthlyQuotaGB.toFixed(0)} GB`;

    quotaProgressBar.style.width = `${Math.min(100, percentageUsed).toFixed(2)}%`;
    document.getElementById('quotaPercentage').textContent = `${percentageUsed.toFixed(0)}%`;

    // Set progress bar color
    if (percentageUsed < 50) {
        quotaProgressBar.className = 'progress-bar progress-green';
    } else if (percentageUsed < 60) {
        quotaProgressBar.className = 'progress-bar progress-yellow';
    } else if (percentageUsed < 75) {
        quotaProgressBar.className = 'progress-bar progress-orange';
    } else {
        quotaProgressBar.className = 'progress-bar progress-red';
    }

    // Set warning message
    const today = new Date();
    const dayOfMonth = today.getDate();
    const daysInMonth = new Date(today.getFullYear(), today.getMonth() + 1, 0).getDate();

    let message = '';
    if (percentageUsed >= 85) {
        message = 'Warning: You are near or have exceeded your monthly quota!';
    } else if (percentageUsed >= 55 && dayOfMonth <= 15) {
        message = 'Red Flag: High usage early in the month!';
    } else if (percentageUsed >= 70) {
        message = 'High usage this month.';
    }
    else {
        message = 'Usage is well within limits.';
    }
    quotaMessageElement.textContent = message;
}

function formatBytes(gbytes) {
    if (gbytes < 1) {
        const mbytes = gbytes * 1024;
        return `${Math.round(mbytes)} MB`;
    }
    return `${gbytes.toFixed(2)} GB`;
}

function calculateAnomalyPercent(device, daysInPeriod) {
    const dailyTraffic = device.daily_traffic || [];
    const totalBytesInPeriod = device.total_bytes || 0;
    const totalGBInPeriod = device.total || 0;

    const SINGLE_DAY_HIGH_USAGE_THRESHOLD_GB = 4;

    if (daysInPeriod === 1) {
        if (totalGBInPeriod > SINGLE_DAY_HIGH_USAGE_THRESHOLD_GB) {
            return 999;
        } else {
            return 0;
        }
    }

    if (dailyTraffic.length <= 1 || totalBytesInPeriod === 0) {
        return 0;
    }

    const mostRecentDayBytes = dailyTraffic[dailyTraffic.length - 1].total_bytes || 0;
    const avgDailyBytesInPeriod = totalBytesInPeriod / daysInPeriod;

    if (avgDailyBytesInPeriod === 0) {
        return 0;
    }

    const recentVsAvg = ((mostRecentDayBytes - avgDailyBytesInPeriod) / avgDailyBytesInPeriod) * 100;

    return recentVsAvg;
}

function updateMainStats(stats, filterType, daysInPeriod) {
    document.getElementById('totalTraffic').textContent = formatBytes(stats.traffic);
    document.getElementById('totalDownload').textContent = formatBytes(stats.dl);
    document.getElementById('totalUpload').textContent = formatBytes(stats.ul);
    document.getElementById('totalDevices').textContent = stats.devices;

    const avgDailyTrafficBox = document.getElementById('avgDailyTrafficBox');
    const avgDailyTrafficElement = document.getElementById('avgDailyTraffic');

    if (daysInPeriod > 1) {
        const avgDailyTraffic = stats.traffic / daysInPeriod;
        avgDailyTrafficElement.textContent = formatBytes(avgDailyTraffic);
        avgDailyTrafficBox.style.display = 'block';
    } else {
        avgDailyTrafficBox.style.display = 'none';
    }

    updateQuotaDisplay(stats, filterType); // Pass filterType along
}

function renderTable(devices) {
    const tableBody = document.getElementById('deviceTableBody');
    tableBody.innerHTML = devices.map(d => {
        const totalVal = d.total;
        const trafficClass = totalVal > 40 ? 'traffic-high' : totalVal > 10 ? 'traffic-medium' : 'traffic-low';
        return `<tr>
                    <td><input type="checkbox" class="device-checkbox" data-mac="${d.mac}" onchange="handleSelectionChange('${d.mac}', this.checked)"></td>
                    <td><span style="cursor: pointer;" onclick="showDeviceCardModal('${d.mac}')">${d.name}</span></td>
                    <td>${d.mac}</td>
                    <td>${formatBytes(d.dl)}</td>
                    <td>${formatBytes(d.ul)}</td>
                    <td>${d.percentage.toFixed(2)}%</td>
                    <td class="${trafficClass}">${formatBytes(d.total)}</td>
                </tr>`;
    }).join('');
    syncCheckboxes();
}

function renderDeviceCards(devices, daysInPeriod) {
    const sevenDayMap = new Map();
    if (sevenDayDataGlobal && sevenDayDataGlobal.devices) {
        sevenDayDataGlobal.devices.forEach(d => {
            sevenDayMap.set(d.mac, d.trend_bytes || []);
        });
    }

    return devices.map(d => {
        const trendBytes = (currentFilterType === 'today' || currentFilterType === 'yesterday') ? (sevenDayMap.get(d.mac) || []) : (d.trend_bytes || []);
        const totalVal = d.total || 0;
        const trafficClass = totalVal > 40 ? 'traffic-high' : totalVal > 10 ? 'traffic-medium' : 'traffic-low';

        const recentVsAvg = calculateAnomalyPercent(d, daysInPeriod);
        const alertClass = recentVsAvg > 18 ? 'alert-high' : 'alert-normal';
        const alertIcon = recentVsAvg > 18 ? '⚠️' : '✅';
        let alertMessage;

        if (recentVsAvg === 999) {
            alertMessage = `High usage: ${formatBytes(d.total)}`;
        } else if (recentVsAvg > 18) {
            alertMessage = `Recent usage is ${recentVsAvg.toFixed(0)}% above this period's avg`;
        } else {
            alertMessage = 'Usage is within normal range';
        }

        return `
        <div class="device-card">
            <div class="card-header">
                <span class="device-name">${d.name || 'Unknown Device'}</span>
                <span class="device-mac">${d.mac || ''}</span>
            </div>
            <div class="card-body">
                <div class="stat-row">
                    <span>Total Usage:</span>
                    <span class="${trafficClass}">${formatBytes(d.total)} (${(d.percentage || 0).toFixed(1)}%)</span>
                </div>
                <div class="stat-row">
                    <span>Download:</span>
                    <span>${formatBytes(d.dl)}</span>
                </div>
                <div class="stat-row">
                    <span>Upload:</span>
                    <span>${formatBytes(d.ul)}</span>
                </div>
            </div>
            <div class="card-footer">
                 <div class="stat-row">
                    <span>Avg Daily:</span>
                    <span>${d.avg_daily_gb > 0 ? formatBytes(d.avg_daily_gb) : 'N/A'}</span>
                </div>
                 <div class="stat-row">
                    <span>Peak Day:</span>
                    <span>${d.peak_day && d.peak_day.gb > 0 ? `${d.peak_day.date.slice(5)} (${formatBytes(d.peak_day.gb)})` : 'N/A'}</span>
                </div>
                <div class="trend-row">
                    <span>Trend:</span>
                    ${(currentFilterType === 'today' || currentFilterType === 'yesterday') ? renderDeviceBarChart(trendBytes) : generateSparkline(trendBytes)}
                </div>
                <div class="screenshot-icon-container">
                    <span class="screenshot-icon" onclick="showDeviceCardModal('${d.mac}', true)">📸</span>
                </div>
                <div class="alert-row ${alertClass}">
                    ${alertIcon} ${alertMessage}
                </div>
                <div class="percentage-bar-container">
                    <div class="percentage-bar ${trafficClass}" style="width: ${(d.percentage || 0).toFixed(1)}%;"></div>
                </div>
            </div>
        </div>`;
    }).join('');
}

function generateSparkline(data) {
    if (!data || data.length === 0) return '<span>No data</span>';
    const width = 100;
    const height = 20;
    const max = Math.max(...data);
    const points = data.map((d, i) => {
        const x = (width / (data.length - 1)) * i;
        const y = height - (d / max) * height;
        return `${x},${y}`;
    }).join(' ');

    return `<svg viewbox="0 0 ${width} ${height}" class="sparkline"><polyline points="${points}" fill="none" stroke="#0d6efd" stroke-width="1"></polyline></svg>`;
}

function renderDeviceBarChart(data) {
    if (!data || data.length === 0) return '<span>No data</span>';
    const width = 120;
    const height = 24;
    const barWidth = 12; // Fixed bar width
    const gap = 2;
    const max = Math.max(...data);
    const numBars = data.length;

    const bars = data.map((d, i) => {
        const barHeight = (d / max) * height;
        const x = width - (numBars - i) * (barWidth + gap);
        const y = height - barHeight;
        const isToday = i === data.length - 1;
        return `<rect x="${x}" y="${y}" width="${barWidth}" height="${barHeight}" fill="${isToday ? '#0d6efd' : '#6c757d'}" rx="1"></rect>`;
    }).join('');

    return `<svg viewbox="0 0 ${width} ${height}" class="sparkline-bar-chart">${bars}</svg>`;
}

function filterContent() {
    const filter = document.getElementById('deviceSearch').value.toUpperCase();
    const isMobile = window.matchMedia('(max-width: 768px)').matches;

    if (isMobile) {
        const cards = document.querySelectorAll('.device-card');
        cards.forEach(card => {
            const deviceName = card.querySelector('.device-name').textContent.toUpperCase();
            const macAddress = card.querySelector('.device-mac').textContent.toUpperCase();
            if (deviceName.indexOf(filter) > -1 || macAddress.indexOf(filter) > -1) {
                card.style.display = "";
            } else {
                card.style.display = "none";
            }
        });
    } else {
        const tr = document.getElementById('deviceTableBody').getElementsByTagName('tr');
        for (let i = 0; i < tr.length; i++) {
            tr[i].style.display = (tr[i].textContent || tr[i].innerText).toUpperCase().indexOf(filter) > -1 ? "" : "none";
        }
    }
}

function renderCharts(barData, pieData, topAppsData) {
    const isMobile = window.matchMedia('(max-width: 768px)').matches;
    renderTopAppsChart(topAppsData);
    document.getElementById('bar-chart-title').textContent = barData.title;
    const pieColors = ['#0d6efd', '#198754', '#ffc107', '#dc3545', '#6f42c1', '#fd7e14', '#20c997', '#6e450c', '#7d7378', '#0dcaf0'];
    if (barChart) barChart.destroy();
    const dailyBarChartCanvas = document.getElementById('dailyBarChart');
    barChart = new Chart(dailyBarChartCanvas.getContext('2d'), {
        type: 'bar',
        data: { labels: barData.labels, datasets: [{ label: 'Total Traffic (GB)', data: barData.values, backgroundColor: 'rgba(13, 110, 253, 0.6)' }] },
        options: { responsive: true, plugins: { legend: { display: false } } }
    });

    // Add click event listener to the bar chart
    dailyBarChartCanvas.onclick = (event) => {
        const points = barChart.getElementsAtEventForMode(event, 'nearest', { intersect: true }, true);
        if (points.length) {
            const firstPoint = points[0];
            const label = barChart.data.labels[firstPoint.index];
            console.log("Date label from chart click:", label);
            showDailyBreakdownModal(label);
        }
    };

    if (pieChart) pieChart.destroy();
    pieChart = new Chart(document.getElementById('devicePieChart').getContext('2d'), {
        type: 'doughnut',
        data: {
            labels: pieData.map(d => d.name),
            datasets: [{
                data: pieData.map(d => d.total),
                backgroundColor: pieColors,
                // Store percentage data directly in the dataset for the tooltip
                percentage: pieData.map(d => d.percentage)
            }]
        },
        options: {
            responsive: true,
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        filter: function (legendItem, chartData) {
                            return true; // Always show all legend items
                        },
                        boxWidth: isMobile ? 10 : 40, // Use 10px box on mobile
                        padding: isMobile ? 8 : 10, // Use 8px padding on
                        font: {
                            size: isMobile ? 11 : undefined // Increase mobile font size by +1
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            // Robustness check: ensure dataset and percentage exist before access
                            if (context.dataset && context.dataset.percentage && context.dataset.percentage[context.dataIndex] !== undefined) {
                                const value = context.raw || 0;
                                const percentage = context.dataset.percentage[context.dataIndex];
                                return `${formatBytes(value)} (${percentage.toFixed(2)}%)`;
                            }
                            // Fallback to default label if custom data isn't ready
                            return context.label + ': ' + formatBytes(context.raw);
                        }
                    }
                }
            }
        }
    });
}

function renderTopAppsChart(topAppsData) {
    const existingChart = Chart.getChart('topAppsChart');
    if (existingChart) {
        existingChart.destroy();
    }
    const appNames = topAppsData.map(app => app.name);
    const appTotals = topAppsData.map(app => app.total);

    const backgroundColors = appNames.map((_, i) => `rgba(25, 135, 84, ${1 - (i * 0.05)})`);
    const borderColorsArray = appNames.map((_, i) => `rgba(25, 135, 84, ${1 - (i * 0.05)})`);

    const isMobile = window.matchMedia('(max-width: 768px)').matches;

    const chartOptions = {
        responsive: true,
        maintainAspectRatio: !isMobile,
        indexAxis: 'y',
        plugins: {
            legend: {
                display: false
            },
            title: {
                display: true,
                text: 'Top Applications/Websites by Traffic'
            },
            tooltip: {
                callbacks: {
                    label: function (context) {
                        let label = context.dataset.label || '';
                        if (label) {
                            label += ': ';
                        }
                        const value = context.raw;
                        const total = context.dataset.data.reduce((sum, val) => sum + val, 0);
                        const percentage = (value / total * 100).toFixed(2);
                        return `${label}${formatBytes(value)} (${percentage}%)`;
                    }
                }
            }
        },
        scales: {
            x: {
                beginAtZero: true,
                title: {
                    display: true,
                    text: 'Traffic (GB)'
                }
            },
            y: {
                beginAtZero: true,
                ticks: {
                    autoSkip: false,
                    font: {
                        size: isMobile ? 9 : 12
                    },
                    padding: isMobile ? 8 : 0
                }
            }
        }
    };

    topAppsChart = new Chart(document.getElementById('topAppsChart').getContext('2d'), {
        type: 'bar',
        data: {
            labels: appNames,
            datasets: [{
                label: 'Total Traffic',
                data: appTotals,
                backgroundColor: backgroundColors,
                borderColor: borderColorsArray,
                borderWidth: 1
            }]
        },
        options: chartOptions
    });
}

async function fetchData(filename) {
    let path;
    path = `/skyhero-v2/data/period_data/${filename}`;

    try {
        const response = await fetch(path);
        if (!response.ok) {
            throw new Error(`HTTP error! status: ${response.status}`);
        }
        return await response.json();
    } catch (error) {
        console.error("Could not fetch data: ", error);
        return null;
    }
}

async function applyFilter(filterType) {
    // Defensive check to prevent errors if filterType is undefined or invalid
    if (typeof filterType === 'undefined' || filterType === null) {
        console.error("applyFilter called with invalid filterType:", filterType);
        return; // Exit the function early
    }
    
    // Additional validation to prevent crashes from invalid filterType values
    if (typeof filterType !== 'string') {
        console.error("applyFilter called with non-string filterType:", filterType);
        return; // Exit the function early
    }
    
    console.log("applyFilter called with filterType:", filterType);
    let filename;
    let sevenDayData = null;

    let daysInPeriod = 0;

    const allTimeData = await fetchData('traffic_period_all_time.json');
    if (allTimeData && allTimeData.barChart && allTimeData.barChart.labels && allTimeData.barChart.labels.length > 0) {
        routerTodayFormatted = allTimeData.barChart.labels[allTimeData.barChart.labels.length - 1];
    } else {
        const today = new Date();
        const yyyy = today.getFullYear();
        const mm = String(today.getMonth() + 1).padStart(2, '0');
        const dd = String(today.getDate()).padStart(2, '0');
        routerTodayFormatted = `${yyyy}-${mm}-${dd}`;
        console.warn("Could not determine router's date from all_time_data.json. Falling back to client date.");
    }

    const todayDate = new Date(routerTodayFormatted);

    const isDateFilter = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(filterType);
    const isMonthFilter = filterType.startsWith('month_');

    console.log("isDateFilter:", isDateFilter);
    console.log("isMonthFilter:", isMonthFilter);

    if (isDateFilter) {
        filename = `traffic_period_${filterType}_${filterType}.json`;
        daysInPeriod = 1;
        sevenDayData = await fetchData('traffic_period_last-7-days.json');
        sevenDayDataGlobal = sevenDayData;
    } else if (isMonthFilter) {
        const month = filterType.split('_')[1];
        filename = `traffic_month_${month}.json`;
        sevenDayDataGlobal = null;
    } else {
        switch (filterType) {
            case 'all_time':
                filename = 'traffic_period_all_time.json';
                sevenDayDataGlobal = null;
                break;
            case 'today':
                filename = `traffic_period_${routerTodayFormatted}_${routerTodayFormatted}.json`;
                daysInPeriod = 1;
                sevenDayData = await fetchData('traffic_period_last-7-days.json');
                sevenDayDataGlobal = sevenDayData;
                break;
            case 'yesterday':
                // Try multiple possible dates for yesterday, use the first one with data
                const today = new Date();
                const yesterday1 = new Date(today);
                yesterday1.setDate(today.getDate() - 1);
                const yesterday2 = new Date(today);
                yesterday2.setDate(today.getDate() - 2);
                
                const y1Str = `${yesterday1.getFullYear()}-${String(yesterday1.getMonth() + 1).padStart(2, '0')}-${String(yesterday1.getDate()).padStart(2, '0')}`;
                const y2Str = `${yesterday2.getFullYear()}-${String(yesterday2.getMonth() + 1).padStart(2, '0')}-${String(yesterday2.getDate()).padStart(2, '0')}`;
                
                // Try first candidate
                let yesterdayData = await fetchData(`traffic_period_${y1Str}_${y1Str}.json`);
                if (yesterdayData) {
                    filename = `traffic_period_${y1Str}_${y1Str}.json`;
                } else {
                    // Try second candidate
                    yesterdayData = await fetchData(`traffic_period_${y2Str}_${y2Str}.json`);
                    if (yesterdayData) {
                        filename = `traffic_period_${y2Str}_${y2Str}.json`;
                    } else {
                        // Fallback to first candidate
                        filename = `traffic_period_${y1Str}_${y1Str}.json`;
                    }
                }
                daysInPeriod = 1;
                sevenDayData = await fetchData('traffic_period_last-7-days.json');
                sevenDayDataGlobal = sevenDayData;
                break;
            case 'last_7_days':
                filename = 'traffic_period_last-7-days.json';
                daysInPeriod = 7;
                sevenDayDataGlobal = null;
                break;
            case 'this_month':
                const firstDayOfMonth = `${todayDate.getFullYear()}-${String(todayDate.getMonth() + 1).padStart(2, '0')}-01`;
                filename = `traffic_period_${firstDayOfMonth}_${routerTodayFormatted}.json`;
                sevenDayDataGlobal = null;
                break;
            default:
                console.error("Invalid filter type:", filterType);
                return;
        }
    }

    const data = await fetchData(filename);
    if (!data) {
        console.warn(`Data for ${filterType} (${filename}) not found.`);
        alert(`Data for ${filterType} is not available. Please ensure the daily rollup has run for this date.`);
        return;
    }
    console.log("Fetched data for filter type " + filterType + ":", data);

    if (isDateFilter) {
        currentDisplayStartDate = filterType;
        currentDisplayEndDate = filterType;
    } else if (isMonthFilter) {
        const [year, month] = filterType.split('_')[1].split('-');
        currentDisplayStartDate = `${year}-${month}-01`;
        const lastDay = new Date(year, month, 0).getDate();
        currentDisplayEndDate = `${year}-${month}-${String(lastDay).padStart(2, '0')}`;
        const startDate = new Date(currentDisplayStartDate);
        const endDate = new Date(currentDisplayEndDate);
        daysInPeriod = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24)) + 1;
    } else if (filterType === 'last_7_days' || filterType === 'all_time') {
        if (data.barChart && data.barChart.labels && data.barChart.labels.length > 0) {
            currentDisplayStartDate = data.barChart.labels[0];
            currentDisplayEndDate = data.barChart.labels[data.barChart.labels.length - 1];
            const startDate = new Date(currentDisplayStartDate);
            const endDate = new Date(currentDisplayEndDate);
            daysInPeriod = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24)) + 1;
        }
    } else {
        const parts = filename.split('_');
        if (parts.length >= 4) {
            currentDisplayStartDate = parts[2];
            currentDisplayEndDate = parts[3].replace('.json', '');
            const startDate = new Date(currentDisplayStartDate);
            const endDate = new Date(currentDisplayEndDate);
            daysInPeriod = Math.ceil((endDate - startDate) / (1000 * 60 * 60 * 24)) + 1;
        } else {
            currentDisplayStartDate = routerTodayFormatted;
            currentDisplayEndDate = routerTodayFormatted;
            daysInPeriod = 1;
        }
    }

    if (isDateFilter) {
        data.devices.forEach(d => {
            d.avg_daily_gb = d.total;
            d.peak_day = { date: filterType, gb: d.total };
        });
    }

    document.querySelectorAll('.quick-filters .quick-filter-button-item').forEach(b => b.classList.remove('active'));
    if (!isDateFilter && !isMonthFilter) {
        const activeButton = document.querySelector(`.quick-filters .quick-filter-button-item[data-filter-type="${filterType}"]`);
        if (activeButton) {
            activeButton.classList.add('active');
        }
    }

    currentDaysInPeriod = daysInPeriod;
    currentFilterType = filterType;
    currentDevices = data.devices;
    document.getElementById('overview-title').textContent = `Period Overview: ${isDateFilter ? filterType : (isMonthFilter ? filterType.replace('month_', 'Month: ') : filterType.replace(/_/g, ' '))}`;

    console.log("Data before rendering:", data);
    updateMainStats(data.stats, filterType, daysInPeriod);
    renderCharts(data.barChart, data.devices.slice(0, 10), data.topApps);

    const isMobile = window.matchMedia('(max-width: 768px)').matches;
    if (isMobile) {
        const container = document.getElementById('device-cards-container');
        container.innerHTML = renderDeviceCards(data.devices, daysInPeriod);
    } else {
        sortTable(currentSort.column, false);
    }
}

function sortTable(col, toggle = true) {
    if (toggle) {
        if (currentSort.column === col) currentSort.ascending = !currentSort.ascending;
        else currentSort.column = col;
    }

    // Updated keyMap to reflect new column order
    const keyMap = ['name', 'mac', 'dl', 'ul', 'percentage', 'total'];
    const sortKey = keyMap[col];
    if (!sortKey) return;

    currentDevices.sort((a, b) => {
        const valA = a[sortKey], valB = b[sortKey];
        const comparison = typeof valA === 'string' ? valA.localeCompare(valB) : (valA || 0) - (valB || 0);
        return currentSort.ascending ? comparison : -comparison;
    });
    renderTable(currentDevices);
}

// --- Smart Grouping --- //
let selectedDevices = [];
let savedGroups = [];
let groupChart;
let editingGroupIndex = -1; // -1 means no group is being edited

function setEditMode(isEditing, groupName = '') {
    const saveGroupBtn = document.getElementById('save-group-btn');
    const cancelUpdateBtn = document.getElementById('cancel-update-btn');
    const groupNameInput = document.getElementById('group-name-input');

    if (isEditing) {
        editingGroupIndex = savedGroups.findIndex(group => group.name === groupName);
        saveGroupBtn.textContent = 'Update Group';
        cancelUpdateBtn.style.display = 'inline-block';
        groupNameInput.value = groupName;
    } else {
        editingGroupIndex = -1;
        saveGroupBtn.textContent = 'Save Group';
        cancelUpdateBtn.style.display = 'none';
        groupNameInput.value = '';
    }
}

function handleSelectionChange(mac, isSelected) {
    const device = currentDevices.find(d => d.mac === mac);
    if (!device) return;

    const isAlreadySelected = selectedDevices.some(d => d.mac === mac);

    if (isSelected && !isAlreadySelected) {
        selectedDevices.push(device);
    } else if (!isSelected) {
        selectedDevices = selectedDevices.filter(d => d.mac !== mac);
    }
    updateGroupingUI();
    syncCheckboxes();
}

function updateGroupingUI() {
    const groupingArea = document.getElementById('grouping-area');
    const pillsContainer = document.getElementById('pills-container');
    const analyticsSummary = document.getElementById('analytics-summary');

    if (selectedDevices.length === 0) {
        groupingArea.style.display = 'none';
        return;
    }
    groupingArea.style.display = 'block';
    renderSavedGroups();

    pillsContainer.innerHTML = '';
    let groupTraffic = 0;
    const chartLabels = [];
    const chartData = [];

    selectedDevices.forEach(device => {
        const pill = document.createElement('div');
        pill.className = 'pill';
        pill.innerHTML = `
            ${device.name}
            <button class="remove-btn" data-mac="${device.mac}">&times;</button>
        `;
        pillsContainer.appendChild(pill);
        groupTraffic += device.total;
        chartLabels.push(device.name);
        chartData.push(device.total);
    });

    const totalNetworkTraffic = currentDevices.reduce((sum, device) => sum + device.total, 0);
    const percentage = (groupTraffic / totalNetworkTraffic * 100).toFixed(2);
    analyticsSummary.innerHTML = `
        Total Group Traffic: <span style="font-weight: normal;">${formatBytes(groupTraffic)}</span> (<span style="color: var(--primary-color);">${percentage}%</span> of total)
    `;

    updateGroupChart(chartLabels, chartData);

    // Ensure chart visibility is consistent with groupChartVisible state
    const chartContainer = document.querySelector('#grouping-area .chart-container');
    const toggleButton = document.getElementById('toggle-group-chart-btn');
    if (chartContainer && toggleButton) {
        if (groupChartVisible) {
            chartContainer.style.display = 'block';
            toggleButton.textContent = 'Hide Chart';
        } else {
            chartContainer.style.display = 'none';
            toggleButton.textContent = 'Show Chart';
        }
    }
}

function updateGroupChart(labels, data) {
    const ctx = document.getElementById('group-chart').getContext('2d');
    if (groupChart) {
        groupChart.destroy();
    }
    groupChart = new Chart(ctx, {
        type: 'pie',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: [
                    '#FF6384', '#36A2EB', '#FFCE56', '#4BC0C0', '#9966FF', '#FF9F40'
                ]
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: function (context) {
                            const value = context.raw || 0;
                            const total = context.dataset.data.reduce((sum, val) => sum + val, 0);
                            const percentage = total > 0 ? (value / total * 100).toFixed(2) : 0;
                            return `${formatBytes(value)} (${percentage}%)`;
                        }
                    }
                }
            }
        }
    });
}

let groupChartVisible = true; // New global variable to track chart visibility

function toggleGroupChart() {
    const chartContainer = document.querySelector('#grouping-area .chart-container');
    const toggleButton = document.getElementById('toggle-group-chart-btn');

    if (chartContainer && toggleButton) {
        groupChartVisible = !groupChartVisible;
        if (groupChartVisible) {
            chartContainer.style.display = 'block';
            toggleButton.textContent = 'Hide Chart';
            // Re-render chart if it was hidden and there are selected devices
            if (selectedDevices.length > 0) {
                updateGroupChart(selectedDevices.map(d => d.name), selectedDevices.map(d => d.total));
            }
        } else {
            chartContainer.style.display = 'none';
            toggleButton.textContent = 'Show Chart';
            if (groupChart) {
                groupChart.destroy();
                groupChart = null;
            }
        }
    }
}

function syncCheckboxes() {
    const selectedMacs = new Set(selectedDevices.map(d => d.mac));
    document.querySelectorAll('.device-checkbox').forEach(checkbox => {
        const mac = checkbox.dataset.mac;
        checkbox.checked = selectedMacs.has(mac);
    });
    updateClearAllIconVisibility();
}

function updateClearAllIconVisibility() {
    const clearAllIcon = document.getElementById('clear-all-devices-icon');
    if (clearAllIcon) {
        if (selectedDevices.length > 0) {
            clearAllIcon.style.display = 'inline-block';
        } else {
            clearAllIcon.style.display = 'none';
        }
    }
}

function renderSavedGroups() {
    const savedGroupsContainer = document.getElementById('saved-groups-container');
    if (savedGroups.length === 0) {
        savedGroupsContainer.style.display = 'none';
    } else {
        savedGroupsContainer.style.display = 'block';
        savedGroupsContainer.innerHTML = '<h5>Saved Groups:</h5>';
        savedGroups.forEach((group, index) => {
            const pill = document.createElement('div');
            pill.className = 'saved-group-pill';
            pill.textContent = group.name;
            pill.dataset.index = index;
            savedGroupsContainer.appendChild(pill);
        });
        // Add Clear All button
        const clearAllBtn = document.createElement('button');
        clearAllBtn.textContent = 'Clear All';
        clearAllBtn.className = 'clear-all-saved-groups-btn';
        savedGroupsContainer.appendChild(clearAllBtn);

        // Add Hide Grouping button
        const hideGroupingBtn = document.createElement('button');
        hideGroupingBtn.textContent = 'Hide Filters';
        hideGroupingBtn.className = 'hide-grouping-btn';
        savedGroupsContainer.appendChild(hideGroupingBtn);
    }
}

// --- CORRECTED DOMContentLoaded LISTENER ---

document.addEventListener('DOMContentLoaded', async () => {

    // Initialize palestineKidContainer here so it's available globally within this scope
    palestineKidContainer = document.getElementById('palestineKidContainer');

    // --- AUTHENTICATION LOGIC ---
    async function checkAuth() {
        try {
            const response = await fetch('auth_status.sh');
            if (!response.ok) {
                throw new Error(`Auth status check failed with status: ${response.status}`);
            }
            const data = await response.json();

            if (data.enabled) {
                // If password is enabled, get the dashboard-content element and blur it
                const dashboardContent = document.getElementById('dashboard-content');
                if (dashboardContent) {
                    dashboardContent.classList.add('blurred');
                }
                document.getElementById('login-overlay').style.display = 'flex';

                // Auto-focus password input on desktop after a short delay to ensure overlay is visible
                const isMobile = window.matchMedia('(max-width: 768px)').matches;
                if (!isMobile) {
                    setTimeout(() => {
                        const passwordInput = document.getElementById('password-input');
                        if (passwordInput) {
                            passwordInput.focus();
                        }
                    }, 100);
                }

                // Control Palestine Kid image visibility based on device type when login overlay appears
                if (palestineKidContainer) {
                    if (isMobile) {
                        palestineKidContainer.style.display = 'block'; // Show on mobile
                        initPalestineKid(); // Start timer/buttons for mobile
                    } else {
                        palestineKidContainer.style.display = 'none'; // Hide on desktop
                    }
                }
            } else {
                // If not enabled, proceed to load the month navigator
                initMonthNavigator();
                // Show Palestine Kid image if not enabled
                palestineKidContainer.style.display = 'block';
                initPalestineKid();
            }
        } catch (e) {
            console.error("Error checking auth status:", e);
            // If auth_status.sh fails, assume no password and load dashboard
            applyFilter('this_month');
            // In case of auth check error, default to showing the image (as if no password)
            palestineKidContainer.style.display = 'block';
            initPalestineKid();
        }
    }

    // Attach event listener for the login form
    const loginForm = document.getElementById('login-form');
    if (loginForm) {
        const passwordInput = document.getElementById('password-input');
        const loginBox = document.querySelector('.login-box');
        const errorMessage = document.getElementById('error-message');

        loginForm.addEventListener('submit', async function (event) {
            event.preventDefault();
            const passwordAttempt = passwordInput.value;

            try {
                const response = await fetch('auth_check.sh', {
                    method: 'POST',
                    headers: { 'Content-Type': 'text/plain' },
                    body: passwordAttempt
                });
                const data = await response.json();

                if (data.success) {
                    document.getElementById('login-overlay').style.display = 'none';
                    const dashboardContent = document.getElementById('dashboard-content');
                    if (dashboardContent) {
                        dashboardContent.classList.remove('blurred');
                    }
                    initMonthNavigator();
                    // Show Palestine Kid image after successful login
                    if (palestineKidContainer) {
                        palestineKidContainer.style.display = 'block';
                    }
                    initPalestineKid();
                } else {
                    errorMessage.classList.add('visible');
                    loginBox.classList.add('shake');
                    passwordInput.classList.add('error'); // Add error class
                    passwordInput.value = '';
                    setTimeout(() => {
                        loginBox.classList.remove('shake');
                    }, 500);
                }
            } catch (e) {
                console.error("Error during authentication:", e);
                errorMessage.textContent = "Authentication error.";
                errorMessage.classList.add('visible');
                passwordInput.classList.add('error'); // Add error class on general auth error
            }
        });

        // Remove error class when user starts typing
        passwordInput.addEventListener('input', () => {
            passwordInput.classList.remove('error');
            errorMessage.classList.remove('visible'); // Hide error message on input
        });

        // Mobile keyboard handling
        const isMobile = window.matchMedia('(max-width: 768px)').matches;
        if (isMobile) {
            const loginOverlay = document.getElementById('login-overlay');

            // Handle virtual keyboard appearance on mobile
            passwordInput.addEventListener('focus', () => {
                setTimeout(() => {
                    loginBox.classList.add('keyboard-active');
                    loginOverlay.classList.add('keyboard-mode');
                }, 300); // Small delay to allow keyboard animation
            });

            passwordInput.addEventListener('blur', () => {
                loginBox.classList.remove('keyboard-active');
                loginOverlay.classList.remove('keyboard-mode');
            });

            // Handle viewport resize (keyboard show/hide)
            let initialViewportHeight = window.innerHeight;
            window.addEventListener('resize', () => {
                const currentHeight = window.innerHeight;
                const heightDifference = initialViewportHeight - currentHeight;

                // If height decreased significantly (keyboard appeared)
                if (heightDifference > 150) {
                    loginBox.classList.add('keyboard-active');
                    loginOverlay.classList.add('keyboard-mode');
                } else {
                    loginBox.classList.remove('keyboard-active');
                    loginOverlay.classList.remove('keyboard-mode');
                }
            });
        }
    }

    // --- ORIGINAL PAGE SETUP LOGIC ---
    checkRestoreStatus(); // Check for restore events on page load

    const billingStartInput = document.getElementById('billingStart');
    const billingDaysSelect = document.getElementById('billingDays');
    const applyBillingFilterBtn = document.querySelector('.billing-controls .apply-btn');

    const initialData = await fetchData('traffic_period_all_time.json');
    if (initialData && initialData.barChart && initialData.barChart.labels.length > 0) {
        billingStartInput.value = initialData.barChart.labels[initialData.barChart.labels.length - 1];
    }

    function showLoader(show) {
        document.getElementById('loader-overlay').style.display = show ? 'flex' : 'none';
    }

    async function pollForReport(filename, timeout = 60000) {
        const pollInterval = 2000;
        const startTime = Date.now();
        return new Promise((resolve, reject) => {
            const intervalId = setInterval(async () => {
                if (Date.now() - startTime > timeout) {
                    clearInterval(intervalId);
                    reject(new Error('Report generation timed out.'));
                    return;
                }
                try {
                    const response = await fetch(`/skyhero-v2/data/period_data/${filename}`);
                    if (response.ok) {
                        clearInterval(intervalId);
                        resolve(await response.json());
                    }
                } catch (error) {
                    // Ignore fetch errors
                }
            }, pollInterval);
        });
    }

    if (applyBillingFilterBtn) {
        applyBillingFilterBtn.addEventListener('click', async () => {
            const startDateStr = billingStartInput.value;
            const days = parseInt(billingDaysSelect.value);
            if (!startDateStr || isNaN(days)) {
                alert('Please select a start date and period.');
                return;
            }
            const startDate = new Date(startDateStr);
            const endDate = new Date(startDate);
            endDate.setDate(startDate.getDate() + days - 1);
            const endDateStr = `${endDate.getFullYear()}-${String(endDate.getMonth() + 1).padStart(2, '0')}-${String(endDate.getDate()).padStart(2, '0')}`;
            const filename = `traffic_period_${startDateStr}_${endDateStr}.json`;

            applyBillingFilterBtn.disabled = true;
            showLoader(true);
            try {
                const cgiResponse = await fetch(`request_generator.sh?start=${startDateStr}&end=${endDateStr}`);
                const cgiData = await cgiResponse.json();
                if (!cgiData.success) {
                    throw new Error(cgiData.message || 'Failed to queue report.');
                }
                const data = await pollForReport(filename);
                document.getElementById('overview-title').textContent = `Period Overview: ${startDateStr} to ${endDateStr}`;
                updateMainStats(data.stats);
                renderCharts(data.barChart, data.devices.slice(0, 10), data.topApps);
                currentDevices = data.devices;
                sortTable(currentSort.column, false);
            } catch (error) {
                console.error('Error during custom report generation:', error);
                alert('Error: ' + error.message);
            } finally {
                showLoader(false);
                applyBillingFilterBtn.disabled = false;
            }
        });
    }

    // Fixed selector to only target actual filter buttons, not navigator arrows
    document.querySelectorAll('.quick-filters .quick-filter-button-item').forEach(button => {
        button.addEventListener('click', () => {
            applyFilter(button.dataset.filterType);
        });
    });

    document.getElementById('next-month').addEventListener('click', () => {
        // Right arrow now moves to a newer month
        if (currentMonthIndex > 0) {
            currentMonthIndex--;
            updateMonthNavigator();
            loadMonthData();
        }
    });

    document.getElementById('prev-month').addEventListener('click', () => {
        // Left arrow now moves to an older month
        if (currentMonthIndex < availableMonths.length - 1) {
            currentMonthIndex++;
            updateMonthNavigator();
            loadMonthData();
        }
    });

    document.getElementById('current-month-display').addEventListener('click', (event) => {
        loadMonthData();
        // Add click feedback
        const target = event.currentTarget;
        target.classList.add('month-display-clicked');
        setTimeout(() => {
            target.classList.remove('month-display-clicked');
        }, 200); // Remove class after 200ms
    });

    // Smart Grouping Event Listeners
    const saveGroupBtn = document.getElementById('save-group-btn');
    const groupNameInput = document.getElementById('group-name-input');
    const savedGroupsContainer = document.getElementById('saved-groups-container');
    const pillsContainer = document.getElementById('pills-container');
    const cancelUpdateBtn = document.getElementById('cancel-update-btn');

    function saveGroup() {
        const name = groupNameInput.value.trim();
        if (name && selectedDevices.length > 0) {
            if (editingGroupIndex !== -1) {
                // Update existing group
                savedGroups[editingGroupIndex] = { name: name, devices: [...selectedDevices] };
            } else {
                // Save new group
                savedGroups.push({ name: name, devices: [...selectedDevices] });
            }
            setEditMode(false); // Exit edit mode after saving/updating
            renderSavedGroups();
        }
    }

    if (saveGroupBtn) {
        saveGroupBtn.addEventListener('click', saveGroup);
    }

    if (groupNameInput) {
        groupNameInput.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                event.preventDefault(); // Prevent default form submission
                saveGroup();
            }
        });
    }

    if (cancelUpdateBtn) {
        function resetGroupingUI() {
            selectedDevices = [];
            updateGroupingUI();
            syncCheckboxes();
            // Hide saved groups container and the hide filters button
            const savedGroupsContainer = document.getElementById('saved-groups-container');
            const hideGroupingBtn = document.querySelector('.hide-grouping-btn');
            if (savedGroupsContainer) {
                savedGroupsContainer.style.display = 'none';
            }
            if (hideGroupingBtn) {
                hideGroupingBtn.style.display = 'none';
            }
            updateClearAllIconVisibility(); // Ensure icon visibility is updated
        }

        cancelUpdateBtn.addEventListener('click', () => {
            setEditMode(false);
            resetGroupingUI();
        });
    }

    if (savedGroupsContainer) {
        savedGroupsContainer.addEventListener('click', (e) => {
            if (e.target.classList.contains('saved-group-pill')) {
                const index = parseInt(e.target.dataset.index);
                selectedDevices = [...savedGroups[index].devices];
                updateGroupingUI();
                syncCheckboxes();
                setEditMode(true, savedGroups[index].name); // Enter edit mode
            } else if (e.target.classList.contains('remove-saved-group-btn')) {
                const indexToRemove = parseInt(e.target.dataset.index);
                savedGroups.splice(indexToRemove, 1);
                renderSavedGroups();
            } else if (e.target.classList.contains('clear-all-saved-groups-btn')) {
                savedGroups = [];
                renderSavedGroups();
            } else if (e.target.classList.contains('hide-grouping-btn')) {
                resetGroupingUI();
            }
        });
    }

    if (pillsContainer) {
        pillsContainer.addEventListener('click', (e) => {
            if (e.target.classList.contains('remove-btn')) {
                const mac = e.target.dataset.mac;
                handleSelectionChange(mac, false);
            }
        });
    }

    const toggleGroupChartBtn = document.getElementById('toggle-group-chart-btn');
    if (toggleGroupChartBtn) {
        toggleGroupChartBtn.addEventListener('click', toggleGroupChart);
    }

    const clearAllDevicesIcon = document.getElementById('clear-all-devices-icon');
    const checkboxHeader = document.getElementById('checkbox-header');

    if (checkboxHeader) {
        checkboxHeader.addEventListener('click', () => {
            resetGroupingUI();
        });
    }

    // --- INITIAL AUTH CHECK ---
    // This is the very first thing that runs. It will either show the login
    // or call initMonthNavigator() itself upon success.
    checkAuth();

    // Render saved groups on page load
    renderSavedGroups();
});

let palestineKidContainer;
let countdownInterval;
let countdownSpan;
let hidePalestineKidButton;
let keepPalestineKidButton;

function initPalestineKid() {
    palestineKidContainer = document.getElementById('palestineKidContainer');
    hidePalestineKidButton = document.getElementById('hidePalestineKid');
    countdownSpan = document.getElementById('countdownSpan');
    keepPalestineKidButton = document.getElementById('keepPalestineKid');

    if (palestineKidContainer && hidePalestineKidButton && countdownSpan && keepPalestineKidButton) {
        palestineKidContainer.style.display = 'block'; // Ensure it's visible when initialized
        countdownSpan.style.display = 'inline';
        keepPalestineKidButton.style.display = 'inline';

        let countdown = 30;
        countdownSpan.textContent = `(${countdown}s)`;

        if (countdownInterval) {
            clearInterval(countdownInterval);
        }

        countdownInterval = setInterval(() => {
            countdown--;
            countdownSpan.textContent = `(${countdown}s)`;
            if (countdown <= 0) {
                clearInterval(countdownInterval);
                palestineKidContainer.style.display = 'none';
            }
        }, 1000);

        hidePalestineKidButton.addEventListener('click', () => {
            clearInterval(countdownInterval);
            palestineKidContainer.style.display = 'none';
        });

        keepPalestineKidButton.addEventListener('click', () => {
            clearInterval(countdownInterval);
            countdownSpan.style.display = 'none';
        });
    }
}
