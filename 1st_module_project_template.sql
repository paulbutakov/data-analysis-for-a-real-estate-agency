/* Проект: анализ данных для агентства недвижимости
 *
 * 
 * Автор: Бутаков Павел
 * Дата: 14.03.2025
*/

-- Время активности объявлений
-- WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Фильтруем данные и оставляем только города Ленобласти и Санкт-Петербург:
filtered_data AS (
    SELECT
        a.id,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        f.city_id,
        c.city,
        t.type
    FROM
        real_estate.advertisement AS a
    JOIN
        real_estate.flats AS f ON a.id = f.id
    JOIN
        real_estate.city AS c ON f.city_id = c.city_id
    JOIN
        real_estate.type AS t ON f.type_id = t.type_id 
    WHERE
        a.days_exposition IS NOT NULL AND
        a.days_exposition > 0 AND
        f.total_area > 0 AND
        a.last_price > 0 AND
        f.id IN (SELECT id FROM filtered_id) AND -- Фильтрация аномальных значений
        t.type = 'город'  -- Фильтруем по типу город
),
-- Категоризируем данные:
categorized_data AS (
    SELECT
        id,
        days_exposition,
        last_price,
        total_area,
        rooms,
        balcony,
        city,
        CASE
            WHEN city = 'Санкт-Петербург' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        CASE
            WHEN days_exposition <= 30 THEN 'до месяца'
            WHEN days_exposition <= 90 THEN 'до трёх месяцев'
            WHEN days_exposition <= 180 THEN 'до полугода'
            ELSE 'более полугода'
        END AS time_category
    FROM
        filtered_data
),
-- Агрегируем данные:
final_data AS (
    SELECT
        region,
        time_category,
        COUNT(*) AS ad_count,
        ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_price_per_sqm,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(rooms)::numeric, 2) AS avg_rooms,
        ROUND(AVG(balcony)::numeric, 2) AS avg_balcony
    FROM
        categorized_data
    GROUP BY
        region,
        time_category
)
-- Выводим результаты:
SELECT
    region,
    time_category,
    ad_count,
    avg_price_per_sqm,
    avg_total_area,
    avg_rooms,
    avg_balcony
FROM
    final_data
ORDER BY
    region,
    time_category;

-- Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Фильтруем данные и оставляем только города Ленобласти и Санкт-Петербург:
filtered_data AS (
    SELECT
        a.id,
        a.first_day_exposition,
        a.days_exposition,
        a.last_price,
        f.total_area,
        c.city,
        DATE(a.first_day_exposition + INTERVAL '1 day' * a.days_exposition) AS removal_date
    FROM
        real_estate.advertisement AS a
    JOIN
        real_estate.flats AS f ON a.id = f.id
    JOIN
        real_estate.city AS c ON f.city_id = c.city_id
    WHERE
        a.days_exposition IS NOT NULL AND
        a.days_exposition > 0 AND
        f.total_area > 0 AND
        a.last_price > 0 AND
        f.id IN (SELECT id FROM filtered_id) AND -- Фильтрация аномальных значений
        c.city IN ('Санкт-Петербург', 'Гатчина', 'Выборг', 'Всеволожск', 'Колпино', 'Пушкин', 'Парголово', 'Петергоф', 'Сестрорецк', 'Красное Село', 'Новое Девяткино', 'Сертолово', 'Ломоносов') -- Оставляем только города Ленобласти и Санкт-Петербург
),
-- Исключаем неполные годы:
complete_years AS (
    SELECT
        EXTRACT(YEAR FROM first_day_exposition) AS year
    FROM
        filtered_data
    WHERE EXTRACT(YEAR FROM first_day_exposition) NOT IN (2014, 2019)
    GROUP BY
        year
),
-- Анализ по месяцам публикации:
publication_stats AS (
    SELECT
        EXTRACT(MONTH FROM first_day_exposition) AS publication_month,
        COUNT(*) AS publication_count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS publication_percentage,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_price_per_sqm,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS publication_rank
    FROM
        filtered_data
    WHERE
        EXTRACT(YEAR FROM first_day_exposition) IN (SELECT year FROM complete_years)
    GROUP BY
        publication_month
),
-- Анализ по месяцам снятия:
removal_stats AS (
    SELECT
        EXTRACT(MONTH FROM removal_date) AS removal_month,
        COUNT(*) AS removal_count,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS removal_percentage,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_price_per_sqm,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS removal_rank
    FROM
        filtered_data
    WHERE
        EXTRACT(YEAR FROM removal_date) IN (SELECT year FROM complete_years)
    GROUP BY
        removal_month
)
-- Выводим результаты для месяцев публикации:
SELECT
    'publication' AS type,
    publication_month AS month,
    publication_count,
    publication_percentage,
    avg_total_area,
    avg_price_per_sqm,
    publication_rank
FROM
    publication_stats
UNION ALL
-- Выводим результаты для месяцев снятия:
SELECT
    'removal' AS type,
    removal_month AS month,
    removal_count,
    removal_percentage,
    avg_total_area,
    avg_price_per_sqm,
    removal_rank
FROM
    removal_stats
ORDER BY
    type,
    month;

-- Анализ рынка недвижимости Ленобласти

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
filtered_data AS (
    SELECT
        a.id,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.city_id,
        c.city
    FROM
        real_estate.advertisement AS a
    JOIN
        real_estate.flats AS f ON a.id = f.id
    JOIN
        real_estate.city AS c ON f.city_id = c.city_id
    WHERE
        c.city != 'Санкт-Петербург' 
        AND f.total_area > 0 
        AND a.last_price > 0
        AND a.id IN (SELECT id FROM filtered_id) -- Фильтрация по выбросам
),
city_stats AS (
    SELECT
        city,
        COUNT(*) AS total_ads,
        COUNT(CASE WHEN days_exposition IS NOT NULL AND days_exposition > 0 THEN 1 END) AS removed_ads,
        ROUND(AVG(last_price / total_area)::numeric, 2) AS avg_price_per_sqm,
        ROUND(AVG(total_area)::numeric, 2) AS avg_total_area,
        ROUND(AVG(NULLIF(days_exposition, 0))::numeric, 2) AS avg_days_exposition
    FROM
        filtered_data
    GROUP BY
        city
    HAVING
        COUNT(*) > 50 
)
SELECT
    city,
    total_ads,
    removed_ads,
    ROUND((removed_ads * 100.0 / total_ads)::numeric, 2) AS removal_rate,
    avg_price_per_sqm,
    avg_total_area,
    avg_days_exposition
FROM
    city_stats
ORDER BY
    total_ads DESC
LIMIT 15;
