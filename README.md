Вот подробный, структурированный промпт для создания индикатора SMC Venom BPR на MQL5. Его можно передать AI-ассистенту (например, мне или Claude) или разработчику для генерации кода.

---

## 📋 ПРОМПТ ДЛЯ СОЗДАНИЯ ИНДИКАТОРА «SMC Venom BPR» (MQL5)

**Роль:** Ты — опытный MQL5-разработчик, специализирующийся на индикаторах Smart Money Concepts (SMC) и ICT.

**Задача:** Написать полнофункциональный пользовательский индикатор для MetaTrader 5 (`#property indicator_chart_window`), который автоматически обнаруживает и визуализирует зоны **BPR (Balanced Price Range)**, **FVG (Fair Value Gap)** и **Breaker Blocks** в рамках торговой модели **ICT Venom**, а также генерирует торговые сигналы с учётом временного фактора.

---

### 1. ОПРЕДЕЛЕНИЯ И ЛОГИКА РАСЧЁТА

#### 1.1. FVG (Fair Value Gap / Imbalance)
Трёхсвечная структура:
- **Бычий FVG (Bullish FVG):** Low свечи [i] > High свечи [i+2] → зона между ними.
- **Медвежий FVG (Bearish FVG):** High свечи [i] < Low свечи [i+2] → зона между ними.

#### 1.2. BPR (Balanced Price Range)
Зона, где **пересекаются** (накладываются) бычий и медвежий FVG, сформированные близко по времени (в пределах N баров). BPR — это «справедливая» зона, где цена была сбалансирована; она часто выступает как магнит и уровень реакции.
- Верхняя граница BPR = max(Low бычьего FVG, Low медвежьего FVG)
- Нижняя граница BPR = min(High бычьего FVG, High медвежьего FVG)
- Условие валидности: верхняя граница > нижней границы (есть реальный overlap).

#### 1.3. Breaker Block (BB)
- **Бычий Breaker:** последняя медвежья свинг-свеча перед импульсным бычьим движением, которое пробило предыдущий бычьего экстремума (с ликвидностью). После пробоя эта зона становится поддержкой.
- **Медвежий Breaker:** зеркальная логика.
- Определять через swing high/low с окном подтверждения (left_bars / right_bars).

#### 1.4. Venom-модель (временной фильтр)
Торговые сигналы валидны ТОЛЬКО в окно **New York Session** (по умолчанию 13:00–16:00 UTC, настраивается).
- Сигнал формируется, когда цена входит в зону BPR/BB внутри этого окна + есть подтверждение через MSS (Market Structure Shift) или CHoCH.

---

### 2. АЛГОРИТМ РАБОТЫ ИНДИКАТОРА

1. На каждом новом баре сканировать историю на наличие:
   - FVG (бычьих и медвежьих).
   - BPR (пересечение разнонаправленных FVG).
   - Swing-экстремумов → Breaker Blocks.
2. Отмечать зоны прямоугольниками (`OBJ_RECTANGLE`) с разными цветами.
3. При подходе цены к активной зоне в окне Venom — проверять наличие MSS/CHoCH.
4. Формировать сигнал:
   - `BUY` — цена вошла в бычий BPR/BB в окне Venom + MSS вверх.
   - `SELL` — цена вошла в медвежий BPR/BB в окне Venom + MSS вниз.
5. Сигнал рисуется стрелкой (`OBJ_ARROW`) + отправка push/email/alert.
6. Зоны, которые были полностью заполнены (митигированы), помечать как неактивные (бледный цвет или удаление).

---

### 3. ТЕХНИЧЕСКИЕ ТРЕБОВАНИЯ К КОДУ (MQL5)

- Использовать `OnCalculate()` с обработкой по `rates_total` и `prev_calculated`.
- Индикаторные буферы:
  - `BullishFVG_Up`, `BullishFVG_Dn`
  - `BearishFVG_Up`, `BearishFVG_Dn`
  - `BPR_Up`, `BPR_Dn`
  - `SignalBuffer` (для стрелок: 1 = buy, -1 = sell, 0 = пусто)
- Графические объекты: `OBJ_RECTANGLE` для зон, `OBJ_ARROW` (коды 233/234) для сигналов.
- Поддержка множественных таймфреймов (параметр `InpTimeframe`).
- Корректная работа на истории и в реальном времени.
- Комментарии в коде на русском/английском.
- Свойства `#property indicator_plots`, `#property indicator_buffers`, `#property indicator_color1` и т.д.

---

### 4. ВХОДНЫЕ ПАРАМЕТРЫ (`input`)

```cpp
// --- Общие настройки
input int    InpSwingLeft        = 5;       // Левое плечо для swing-поиска
input int    InpSwingRight       = 2;       // Правое плечо для swing-поиска
input int    InpMaxBarsBack      = 500;     // Глубина анализа истории

// --- FVG / BPR
input double InpMinFVGSize       = 0.0;     // Мин. размер FVG (в пунктах, 0 = авто)
input int    InpBPRWindow        = 10;      // Окно поиска пересечения FVG (баров)
input bool   InpShowFVG          = true;    // Показывать FVG
input bool   InpShowBPR          = true;    // Показывать BPR
input bool   InpShowBreaker      = true;    // Показывать Breaker Blocks

// --- Venom (время)
input int    InpVenomStartHour   = 13;      // Начало окна Venom (серверное время)
input int    InpVenomEndHour     = 16;      // Конец окна Venom
input bool   InpVenomOnly        = true;    // Сигналы ТОЛЬКО в окне Venom

// --- Визуал
input color  InpBullFVGColor     = clrLime;
input color  InpBearFVGColor     = clrRed;
input color  InpBPRColor         = clrDodgerBlue;
input color  InpBreakerColor     = clrOrange;
input int    InpZoneOpacity      = 30;      // Прозрачность зон (0-100)

// --- Сигналы
input bool   InpAlertEnabled     = true;
input bool   InpPushEnabled      = false;
input bool   InpEmailEnabled     = false;
```

---

### 5. ВИЗУАЛИЗАЦИЯ

| Объект | Цвет по умолчанию | Стиль |
|---|---|---|
| Bullish FVG | Lime | Полупрозрачный прямоугольник |
| Bearish FVG | Red | Полупрозрачный прямоугольник |
| BPR (overlap) | DodgerBlue | Полупрозрачный прямоугольник, более насыщенный |
| Bullish Breaker | Orange | Пунктирная рамка |
| Bearish Breaker | OrangeRed | Пунктирная рамка |
| Сигнал BUY | Lime | Стрелка вверх (код 233) |
| Сигнал SELL | Red | Стрелка вниз (код 234) |

---

### 6. СИГНАЛЫ И ОПОВЕЩЕНИЯ

При генерации сигнала отправлять:
- `Alert()` — всплывающее окно в терминале
- `SendNotification()` — push (если `InpPushEnabled`)
- `SendMail()` — email (если `InpEmailEnabled`)

Формат сообщения:
```
[SMC Venom BPR] | Symbol | TF | BUY/SELL @ Price | Zone: BPR/Breaker | Time: HH:MM
```

Защита от спама: один сигнал на зону, повторный — только после митигации и нового формирования.

---

### 7. ОГРАНИЧЕНИЯ И ПРОВЕРКИ

- Проверка корректности входных данных (`InpSwingLeft > 0`, `InpVenomStartHour < InpVenomEndHour`).
- Обработка перерисовки зон при появлении новых баров.
- Очистка удалённых/митигированных зон (цена закрылась полностью внутри зоны).
- Совместимость с любыми символами (Forex, индексы, криптo).

---

### 8. РЕЗУЛЬТАТ

Вернуть **полный, компилируемый `.mq5`-файл** с:
- Корректными `#property` директивами
- Рабочим `OnCalculate()`
- Функциями: `DetectFVG()`, `DetectBPR()`, `DetectBreaker()`, `CheckVenomSignal()`, `DrawZone()`, `SendSignal()`
- Комментариями к ключевым блокам кода

---

💡 **Совет:** Если хочешь, я могу сразу сгенерировать по этому промпту готовый код индикатора на MQL5 — просто скажи «напиши код», и я сделаю полный рабочий `.mq5`-файл.
